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

        isSetup = true
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
            let key  = try KeyDerivation.deriveSymmetricKey(password: password, salt: salt)
            return (false, true, SymmetricKey?.some(key))
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
        isSetup = false
    }

    private func hasStoredCredentials() -> Bool {
        (try? KeychainManager.load(key: passwordHashKey)) != nil
    }
}
