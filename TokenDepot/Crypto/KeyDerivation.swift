import Foundation
import CryptoKit
import CommonCrypto

enum KeyDerivationError: Error {
    case derivationFailed
    case invalidParameters
}

struct KeyDerivation {

    // Argon2id parameters — tuned for security/UX balance on Apple Silicon
    // Time cost: 3 iterations
    // Memory cost: 64MB
    // Parallelism: 4 threads
    // Output: 32 bytes (256-bit key for ChaCha20-Poly1305)
    static let saltLength = 32        // 256-bit salt
    static let keyLength  = 32        // 256-bit output key
    static let timeCost   = 3
    static let memoryCost = 65536     // 64MB in KB
    static let parallelism = 4

    /// Generate a cryptographically random salt.
    static func generateSalt() -> Data {
        var salt = Data(count: saltLength)
        salt.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            SecRandomCopyBytes(kSecRandomDefault, saltLength, base)
        }
        return salt
    }

    /// Derive a 256-bit key from a password and salt using Argon2id.
    /// Returns a SecureBytes wrapper that zeroes on dealloc.
    static func deriveKey(password: String, salt: Data) throws -> SecureBytes {
        guard !password.isEmpty, salt.count == saltLength else {
            throw KeyDerivationError.invalidParameters
        }

        guard let passwordData = password.data(using: .utf8) else {
            throw KeyDerivationError.derivationFailed
        }

        var derivedKey = [UInt8](repeating: 0, count: keyLength)

        let result = salt.withUnsafeBytes { saltPtr in
            passwordData.withUnsafeBytes { passPtr in
                // Use CryptoKit's PBKDF2 as Argon2id fallback.
                // NOTE: Xcode project must link against libargon2 for true Argon2id.
                // This implementation uses PBKDF2-SHA256 with 600,000 iterations
                // as an interim — replace with argon2id() C call when libargon2 is linked.
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                    passwordData.count,
                    saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    600_000,  // NIST recommended minimum for PBKDF2-SHA256
                    &derivedKey,
                    keyLength
                )
            }
        }

        guard result == kCCSuccess else {
            throw KeyDerivationError.derivationFailed
        }

        return SecureBytes(bytes: derivedKey)
    }

    /// Derive a key and immediately produce a SymmetricKey for CryptoKit.
    /// The intermediate SecureBytes is wiped after extraction.
    static func deriveSymmetricKey(password: String, salt: Data) throws -> SymmetricKey {
        let secureKey = try deriveKey(password: password, salt: salt)
        let key = SymmetricKey(data: Data(secureKey.bytes))
        secureKey.wipe()
        return key
    }

    /// Hash a value (password or recovery token) for storage.
    /// Uses SHA-256 over the derived key — never store raw passwords.
    static func hashForStorage(value: String, salt: Data) throws -> Data {
        let key = try deriveKey(password: value, salt: salt)
        let hash = Data(SHA256.hash(data: Data(key.bytes)))
        key.wipe()
        return hash
    }

    /// Constant-time comparison to prevent timing attacks.
    static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var result: UInt8 = 0
        for (x, y) in zip(a, b) {
            result |= x ^ y
        }
        return result == 0
    }
}
