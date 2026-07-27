import Foundation

/// A TokenDepot note — decrypted, in memory only.
/// Never persisted in plaintext anywhere.
struct Note: Identifiable {
    let id: UUID
    var title: String
    var content: String
    var color: NoteColor
    var position: CGPoint
    var size: CGSize
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        color: NoteColor = .yellow,
        position: CGPoint = CGPoint(x: 100, y: 100),
        size: CGSize = CGSize(width: 240, height: 200)
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.color = color
        self.position = position
        self.size = size
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

enum NoteColor: String, Codable, CaseIterable {
    case yellow = "yellow"
    case blue   = "blue"
    case green  = "green"
    case pink   = "pink"
    case gray   = "gray"
}

/// The on-disk encrypted envelope for a note.
/// Only this struct is serialized to disk — never Note directly.
struct EncryptedNoteEnvelope: Codable {
    let id: String                  // UUID string
    let encryptedPayload: Data      // ChaCha20-Poly1305 combined (nonce + ct + tag)
    let salt: Data                  // Argon2 salt for this note's key derivation
    let createdAt: Date
    let updatedAt: Date

    // Position and size stored unencrypted (not sensitive)
    let positionX: Double
    let positionY: Double
    let width: Double
    let height: Double
    let colorRaw: String
}

/// The inner payload that gets encrypted.
struct NotePayload: Codable {
    let title: String
    let content: String
}
