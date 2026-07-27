import Foundation
import LocalAuthentication
import CryptoKit

enum RecoveryError: Error {
    case biometricFailed(String)
    case biometricUnavailable
    case invalidToken
    case tokenMismatch
    case notSetup
}

/// Handles the two-factor recovery flow: TouchID + 32-char token.
/// Both must succeed in sequence — either alone is insufficient.
final class RecoveryManager {

    static let shared = RecoveryManager()

    private let tokenHashKey = "td.recoveryTokenHash"
    private let tokenSaltKey = "td.recoveryTokenSalt"
    private let tokenLength  = 32

    private var biometricPassed = false  // must be true before token check

    private init() {}

    // MARK: — Setup

    /// Generate a recovery token, store its hash, return the raw token (shown once).
    func generateAndStoreToken() throws -> String {
        let token = generateToken()

        let salt = KeyDerivation.generateSalt()
        let hash = try KeyDerivation.hashForStorage(value: token, salt: salt)

        try KeychainManager.store(key: tokenSaltKey, data: salt)
        try KeychainManager.store(key: tokenHashKey, data: hash)

        return token  // Caller displays this once — never stored raw
    }

    // MARK: — Recovery Flow

    /// Step 1: Biometric auth. Must be called before verifyToken.
    func authenticateWithBiometric() async throws {
        biometricPassed = false

        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw RecoveryError.biometricUnavailable
        }

        let reason = "Verify your identity to recover TokenDepot access"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            guard success else { throw RecoveryError.biometricFailed("Authentication denied") }
            biometricPassed = true
        } catch let laError as LAError {
            throw RecoveryError.biometricFailed(laError.localizedDescription)
        }
    }

    /// Step 2: Verify the 32-char recovery token. Biometric must have passed first.
    /// On success, returns a new temp key so the user can set a new password.
    func verifyToken(_ token: String) throws {
        guard biometricPassed else {
            throw RecoveryError.biometricFailed("Complete biometric authentication first")
        }
        guard token.count == tokenLength else {
            throw RecoveryError.invalidToken
        }

        let salt = try KeychainManager.load(key: tokenSaltKey)
        let storedHash = try KeychainManager.load(key: tokenHashKey)
        let candidateHash = try KeyDerivation.hashForStorage(value: token, salt: salt)

        guard KeyDerivation.constantTimeEqual(storedHash, candidateHash) else {
            biometricPassed = false  // Reset — must re-do biometric on next attempt
            throw RecoveryError.tokenMismatch
        }

        // Both factors passed — recovery is authorized
        biometricPassed = false  // Consume the biometric pass
    }

    // MARK: — Private

    /// Generate a 32-character alphanumeric token via CSPRNG.
    /// NOT UUID, NOT random(), NOT arc4random — uses SecRandomCopyBytes.
    private func generateToken() -> String {
        let charset = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")  // Unambiguous chars
        var bytes = [UInt8](repeating: 0, count: tokenLength)
        SecRandomCopyBytes(kSecRandomDefault, tokenLength, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    var isSetup: Bool {
        return (try? KeychainManager.load(key: tokenHashKey)) != nil
    }
}
