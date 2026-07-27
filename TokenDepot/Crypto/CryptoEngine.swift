import Foundation
import CryptoKit

enum CryptoError: Error {
    case encryptionFailed
    case decryptionFailed
    case tamperedData        // Poly1305 auth tag mismatch
    case invalidKey
    case nonceGenerationFailed
}

/// All encryption/decryption for TokenDepot.
/// Uses ChaChaPoly (ChaCha20-Poly1305) exclusively — never raw ChaCha20.
struct CryptoEngine {

    static let nonceLength = 12   // 96-bit nonce per RFC 8439

    // MARK: — Nonce

    /// Generate a cryptographically random 96-bit nonce.
    /// NEVER reuse a nonce with the same key — call this every single save/update.
    static func generateNonce() throws -> ChaChaPoly.Nonce {
        // CryptoKit's Nonce init generates via SecRandomCopyBytes internally
        return try ChaChaPoly.Nonce()
    }

    // MARK: — Encrypt

    /// Encrypt plaintext with ChaCha20-Poly1305.
    /// Returns a SealedBox containing: nonce + ciphertext + Poly1305 auth tag.
    /// The auth tag ensures any tampering is detected on decryption.
    static func encrypt(plaintext: Data, key: SymmetricKey) throws -> Data {
        let nonce = try generateNonce()

        let sealedBox = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce)

        // Combined format: nonce (12) + ciphertext + tag (16)
        return sealedBox.combined
    }

    /// Encrypt a string directly, returning combined encrypted Data.
    static func encrypt(string: String, key: SymmetricKey) throws -> Data {
        guard let data = string.data(using: .utf8) else {
            throw CryptoError.encryptionFailed
        }
        return try encrypt(plaintext: data, key: key)
    }

    // MARK: — Decrypt

    /// Decrypt a ChaChaPoly combined blob.
    /// Poly1305 tag is verified automatically — throws .tamperedData if mismatch.
    static func decrypt(combined: Data, key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try ChaChaPoly.SealedBox(combined: combined)
            return try ChaChaPoly.open(sealedBox, using: key)
        } catch CryptoKitError.authenticationFailure {
            // Auth tag mismatch — data was tampered with on disk
            throw CryptoError.tamperedData
        } catch {
            throw CryptoError.decryptionFailed
        }
    }

    /// Decrypt and return as UTF-8 string.
    static func decryptString(combined: Data, key: SymmetricKey) throws -> String {
        let data = try decrypt(combined: combined, key: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CryptoError.decryptionFailed
        }
        return string
    }

    // MARK: — Key from SecureBytes

    static func symmetricKey(from secureBytes: SecureBytes) -> SymmetricKey {
        return SymmetricKey(data: Data(secureBytes.bytes))
    }
}
