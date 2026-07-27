import Foundation
import CryptoKit

enum AuthError: Error {
    case wrongPassword
    case rateLimited(secondsRemaining: Int)
    case notSetup
    case panicTriggered       // panic password entered — wipe initiated
    case setupFailed
}

/// Manages authentication state, session key, rate limiting, and panic wipe.
final class AuthManager: ObservableObject {

    static let shared = AuthManager()

    @Published var isUnlocked: Bool = false
    @Published var isSetup: Bool = false

    private let rateLimiter = RateLimiter()
    private var sessionKey: SymmetricKey?

    // Keychain keys
    private let passwordHashKey   = "td.passwordHash"
    private let passwordSaltKey   = "td.passwordSalt"
    private let panicHashKey      = "td.panicHash"
    private let panicSaltKey      = "td.panicSalt"

    private init() {
        isSetup = hasStoredCredentials()
    }

    // MARK: — Setup (first launch)

    func setup(password: String, panicPassword: String) throws {
        guard !password.isEmpty, !panicPassword.isEmpty,
              password != panicPassword else {
            throw AuthError.setupFailed
        }

        // Derive and store password hash
        let passSalt = KeyDerivation.generateSalt()
        let passHash = try KeyDerivation.hashForStorage(value: password, salt: passSalt)
        try KeychainManager.store(key: passwordSaltKey, data: passSalt)
        try KeychainManager.store(key: passwordHashKey, data: passHash)

        // Derive and store panic hash
        let panicSalt = KeyDerivation.generateSalt()
        let panicHash = try KeyDerivation.hashForStorage(value: panicPassword, salt: panicSalt)
        try KeychainManager.store(key: panicSaltKey, data: panicSalt)
        try KeychainManager.store(key: panicHashKey, data: panicHash)

        isSetup = true
    }

    // MARK: — Unlock

    /// Attempt to unlock with a password. Returns false on wrong password.
    /// Throws .rateLimited if too many failed attempts.
    /// Throws .panicTriggered if the panic password is entered.
    func unlock(password: String) throws {
        guard isSetup else { throw AuthError.notSetup }

        // Rate limit check
        guard rateLimiter.canAttempt() else {
            throw AuthError.rateLimited(secondsRemaining: rateLimiter.remainingLockSeconds)
        }

        // Check panic password first — if match, wipe everything
        if try isPanicPassword(password) {
            triggerPanicWipe()
            throw AuthError.panicTriggered
        }

        // Verify real password
        guard try isCorrectPassword(password) else {
            rateLimiter.recordFailure()
            throw AuthError.wrongPassword
        }

        // Derive session key and store in memory only
        let salt = try KeychainManager.load(key: passwordSaltKey)
        sessionKey = try KeyDerivation.deriveSymmetricKey(password: password, salt: salt)

        rateLimiter.recordSuccess()
        isUnlocked = true
    }

    // MARK: — Lock

    func lock() {
        // Wipe session key from memory
        sessionKey = nil
        isUnlocked = false
    }

    // MARK: — Session Key Access

    /// Returns the active session key. Nil if locked.
    func activeKey() -> SymmetricKey? {
        return sessionKey
    }

    // MARK: — Rate Limiter Info

    var isRateLimited: Bool { rateLimiter.isLocked }
    var rateLimitSecondsRemaining: Int { rateLimiter.remainingLockSeconds }
    var failedAttempts: Int { rateLimiter.attemptCount }

    // MARK: — Private

    private func isCorrectPassword(_ password: String) throws -> Bool {
        let salt = try KeychainManager.load(key: passwordSaltKey)
        let storedHash = try KeychainManager.load(key: passwordHashKey)
        let candidateHash = try KeyDerivation.hashForStorage(value: password, salt: salt)
        return KeyDerivation.constantTimeEqual(storedHash, candidateHash)
    }

    private func isPanicPassword(_ password: String) throws -> Bool {
        let salt = try KeychainManager.load(key: panicSaltKey)
        let storedHash = try KeychainManager.load(key: panicHashKey)
        let candidateHash = try KeyDerivation.hashForStorage(value: password, salt: salt)
        return KeyDerivation.constantTimeEqual(storedHash, candidateHash)
    }

    private func triggerPanicWipe() {
        // Lock immediately
        lock()
        // Delegate to NoteStore for secure multi-pass wipe
        NoteStore.shared.panicWipeAll()
        // Clear keychain credentials
        try? KeychainManager.delete(key: passwordHashKey)
        try? KeychainManager.delete(key: passwordSaltKey)
        try? KeychainManager.delete(key: panicHashKey)
        try? KeychainManager.delete(key: panicSaltKey)
        isSetup = false
    }

    private func hasStoredCredentials() -> Bool {
        return (try? KeychainManager.load(key: passwordHashKey)) != nil
    }
}
