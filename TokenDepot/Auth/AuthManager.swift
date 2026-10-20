import Foundation
import CryptoKit

enum AuthError: Error {
    case wrongPassword
    case rateLimited(secondsRemaining: Int)
    case notSetup
    case panicTriggered
    case setupFailed
}

/// Manages authentication state, session key, rate limiting, and panic wipe.
final class AuthManager: ObservableObject {

    static let shared = AuthManager()

    @Published var isUnlocked: Bool = false
    @Published var isSetup: Bool = false

    private let rateLimiter = RateLimiter()
    private var sessionKey: SymmetricKey?

    private let passwordHashKey = "td.passwordHash"
    private let passwordSaltKey = "td.passwordSalt"
    private let panicHashKey    = "td.panicHash"
    private let panicSaltKey    = "td.panicSalt"

    // Notes are encrypted with a random vault key that never changes. The vault key is stored
    // wrapped by the password-derived key and (separately) by the recovery-token-derived key,
    // so changing the password only re-wraps the vault key and never touches note files.
    private let vaultWrapKey         = "td.vaultKeyPassword"
    private let vaultRecoveryWrapKey = "td.vaultKeyRecovery"
    private let vaultMigrationKey    = "td.vaultMigrationPending"
    private var pendingVaultKey: SymmetricKey?   // only between setup() and token generation

    private init() {
        isSetup = hasStoredCredentials()
    }

    // MARK: — Setup

    func setup(password: String, panicPassword: String) throws {
        guard !password.isEmpty, !panicPassword.isEmpty,
              password != panicPassword else { throw AuthError.setupFailed }

        let passSalt = KeyDerivation.generateSalt()
        let passHash = try KeyDerivation.hashForStorage(value: password, salt: passSalt)
        try KeychainManager.store(key: passwordSaltKey, data: passSalt)
        try KeychainManager.store(key: passwordHashKey, data: passHash)

        let panicSalt = KeyDerivation.generateSalt()
        let panicHash = try KeyDerivation.hashForStorage(value: panicPassword, salt: panicSalt)
        try KeychainManager.store(key: panicSaltKey, data: panicSalt)
        try KeychainManager.store(key: panicHashKey, data: panicHash)

        let vaultKey = SymmetricKey(size: .bits256)
        let passKey  = try KeyDerivation.deriveSymmetricKey(password: password, salt: passSalt)
        try KeychainManager.store(key: vaultWrapKey, data: wrap(vaultKey, with: passKey))
        pendingVaultKey = vaultKey

        isSetup = true
    }

    // MARK: — Recovery wrap

    /// Wrap the vault key with a key derived from the recovery token so recovery can restore notes.
    /// Requires an unlocked session or a setup in progress.
    func storeRecoveryWrap(token: String, salt: Data) throws {
        guard let vaultKey = sessionKey ?? pendingVaultKey else { throw AuthError.setupFailed }
        let tokenKey = try KeyDerivation.deriveSymmetricKey(password: token, salt: salt)
        try KeychainManager.store(key: vaultRecoveryWrapKey, data: wrap(vaultKey, with: tokenKey))
        pendingVaultKey = nil
    }

    /// Recover the vault key using the recovery token. Throws `.notSetup` if no recovery wrap exists
    /// (installs created before vault keys existed must unlock once and regenerate their token).
    func recoverVaultKey(token: String, salt: Data) throws -> SymmetricKey {
        guard let wrapped = try? KeychainManager.load(key: vaultRecoveryWrapKey) else {
            throw AuthError.notSetup
        }
        let tokenKey = try KeyDerivation.deriveSymmetricKey(password: token, salt: salt)
        return SymmetricKey(data: try CryptoEngine.decrypt(combined: wrapped, key: tokenKey))
    }

    /// Set a new master password for an existing vault key. Note files are untouched.
    func resetPassword(_ newPassword: String, vaultKey: SymmetricKey) throws {
        guard !newPassword.isEmpty else { throw AuthError.setupFailed }
        let salt    = KeyDerivation.generateSalt()
        let passKey = try KeyDerivation.deriveSymmetricKey(password: newPassword, salt: salt)
        let hash    = try KeyDerivation.hashForStorage(value: newPassword, salt: salt)

        // Wrap first: if a later write fails, the old password still verifies against its old salt.
        try KeychainManager.store(key: vaultWrapKey, data: wrap(vaultKey, with: passKey))
        try KeychainManager.store(key: passwordSaltKey, data: salt)
        try KeychainManager.store(key: passwordHashKey, data: hash)
        lock()
    }

    // MARK: — Unlock (async — KDF runs off main thread)

    /// Full async unlock — KDF runs on background thread, never blocks UI.
    func unlock(password: String) async throws {
        guard isSetup else { throw AuthError.notSetup }

        guard rateLimiter.canAttempt() else {
            throw AuthError.rateLimited(secondsRemaining: rateLimiter.remainingLockSeconds)
        }

        // Run expensive KDF operations off main thread
        let (isPanic, isCorrect, derivedKey) = try await Task.detached(priority: .userInitiated) {
            let isPanic   = try self.isPanicPassword(password)
            if isPanic { return (true, false, SymmetricKey?.none) }

            let isCorrect = try self.isCorrectPassword(password)
            if !isCorrect { return (false, false, SymmetricKey?.none) }

            let salt = try KeychainManager.load(key: self.passwordSaltKey)
            let passKey  = try KeyDerivation.deriveSymmetricKey(password: password, salt: salt)
            let vaultKey = try self.openVault(passwordKey: passKey)
            return (false, true, SymmetricKey?.some(vaultKey))
        }.value

        // Back on caller (main) thread for state updates
        if isPanic {
            triggerPanicWipe()
            throw AuthError.panicTriggered
        }

        guard isCorrect, let key = derivedKey else {
            rateLimiter.recordFailure()
            throw AuthError.wrongPassword
        }

        sessionKey = key
        rateLimiter.recordSuccess()
        await MainActor.run { isUnlocked = true }
    }

    // MARK: — Lock

    func lock() {
        // SymmetricKey zeroes its internal buffer on dealloc (CryptoKit guarantee)
        sessionKey = nil
        isUnlocked = false
    }

    // MARK: — Session Key

    func activeKey() -> SymmetricKey? { sessionKey }

    // MARK: — Rate Limiter

    var isRateLimited: Bool { rateLimiter.isLocked }
    var rateLimitSecondsRemaining: Int { rateLimiter.remainingLockSeconds }
    var failedAttempts: Int { rateLimiter.attemptCount }

    // MARK: — Private

    /// Returns the vault key, migrating pre-vault installs (notes encrypted directly with the
    /// password-derived key) on first unlock.
    private func openVault(passwordKey: SymmetricKey) throws -> SymmetricKey {
        let wrapped: Data?
        do { wrapped = try KeychainManager.load(key: vaultWrapKey) }
        catch KeychainError.notFound { wrapped = nil }

        if let wrapped = wrapped {
            let vaultKey = SymmetricKey(data: try CryptoEngine.decrypt(combined: wrapped, key: passwordKey))
            if (try? KeychainManager.load(key: vaultMigrationKey)) != nil {
                // A previous migration was interrupted — finish it.
                try NoteStore.shared.migrate(from: passwordKey, to: vaultKey)
                try? KeychainManager.delete(key: vaultMigrationKey)
            }
            return vaultKey
        }

        let vaultKey = SymmetricKey(size: .bits256)
        try KeychainManager.store(key: vaultMigrationKey, data: Data([1]))
        try KeychainManager.store(key: vaultWrapKey, data: wrap(vaultKey, with: passwordKey))
        try NoteStore.shared.migrate(from: passwordKey, to: vaultKey)
        try? KeychainManager.delete(key: vaultMigrationKey)
        return vaultKey
    }

    private func wrap(_ vaultKey: SymmetricKey, with wrappingKey: SymmetricKey) throws -> Data {
        let raw = vaultKey.withUnsafeBytes { Data($0) }
        return try CryptoEngine.encrypt(plaintext: raw, key: wrappingKey)
    }

    private func isCorrectPassword(_ password: String) throws -> Bool {
        let salt       = try KeychainManager.load(key: passwordSaltKey)
        let stored     = try KeychainManager.load(key: passwordHashKey)
        let candidate  = try KeyDerivation.hashForStorage(value: password, salt: salt)
        return KeyDerivation.constantTimeEqual(stored, candidate)
    }

    private func isPanicPassword(_ password: String) throws -> Bool {
        let salt      = try KeychainManager.load(key: panicSaltKey)
        let stored    = try KeychainManager.load(key: panicHashKey)
        let candidate = try KeyDerivation.hashForStorage(value: password, salt: salt)
        return KeyDerivation.constantTimeEqual(stored, candidate)
    }

    private func triggerPanicWipe() {
        lock()
        NoteStore.shared.panicWipeAll()
        try? KeychainManager.delete(key: passwordHashKey)
        try? KeychainManager.delete(key: passwordSaltKey)
        try? KeychainManager.delete(key: panicHashKey)
        try? KeychainManager.delete(key: panicSaltKey)
        try? KeychainManager.delete(key: vaultWrapKey)
        try? KeychainManager.delete(key: vaultRecoveryWrapKey)
        try? KeychainManager.delete(key: vaultMigrationKey)
        isSetup = false
    }

    private func hasStoredCredentials() -> Bool {
        (try? KeychainManager.load(key: passwordHashKey)) != nil
    }
}
