import Foundation
import CryptoKit

enum NoteStoreError: Error {
    case notUnlocked
    case encodingFailed
    case decodingFailed
    case fileWriteFailed
    case tamperedNote(id: String)
}

/// Manages all note persistence. Encrypted on write, decrypted on read.
/// Notes directory: ~/Library/Application Support/TokenDepot/notes/
final class NoteStore: ObservableObject {

    static let shared = NoteStore()

    @Published private(set) var notes: [Note] = []

    // Tracks tampered note IDs so UI can surface alerts after load
    private(set) var tamperedNoteIDs: [String] = []

    private let fm = FileManager.default
    private var notesDirectory: URL {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TokenDepot/notes", isDirectory: true)
    }

    private init() {
        createDirectoryIfNeeded()
    }

    // MARK: — Load

    func loadAll(key: SymmetricKey) throws {
        let files = try fm.contentsOfDirectory(
            at: notesDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ).filter { $0.pathExtension == "tdnote" }

        var loaded: [Note] = []
        tamperedNoteIDs = []

        for fileURL in files {
            do {
                let note = try loadNote(from: fileURL, key: key)
                loaded.append(note)
            } catch NoteStoreError.tamperedNote(let id) {
                tamperedNoteIDs.append(id)
            }
        }

        notes = loaded.sorted { $0.updatedAt > $1.updatedAt }

        // Post notification so UI can surface tamper alerts
        if !tamperedNoteIDs.isEmpty {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .tamperedNotesDetected,
                    object: self.tamperedNoteIDs
                )
            }
        }
    }

    // MARK: — Save

    func save(note: Note, key: SymmetricKey) throws {
        let envelope = try encrypt(note: note, key: key)
        let data = try JSONEncoder().encode(envelope)
        let fileURL = notesDirectory.appendingPathComponent("\(note.id.uuidString).tdnote")

        // Atomic write — never partial
        try data.write(to: fileURL, options: [.atomic])
        // Owner read/write only
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)

        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = note
        } else {
            notes.insert(note, at: 0)
        }
    }

    // MARK: — Delete

    func delete(note: Note) throws {
        let fileURL = notesDirectory.appendingPathComponent("\(note.id.uuidString).tdnote")
        try SecureWipe.wipeFile(at: fileURL)
        notes.removeAll { $0.id == note.id }
    }

    // MARK: — Panic Wipe

    func panicWipeAll() {
        do {
            try SecureWipe.wipeDirectory(at: notesDirectory)
        } catch {}
        notes = []
        createDirectoryIfNeeded()
    }

    // MARK: — Clear on lock

    func clearMemory() {
        notes = []
        tamperedNoteIDs = []
    }

    // MARK: — Next staggered position for new notes

    func nextNotePosition() -> CGPoint {
        // Stagger each new note 24px down-right from the last one
        // Wrap around after 10 notes to avoid going off screen
        let base = CGPoint(x: 100, y: 100)
        let offset: CGFloat = 24
        let count = CGFloat(notes.count % 10)
        return CGPoint(x: base.x + offset * count, y: base.y + offset * count)
    }

    // MARK: — Private

    private func loadNote(from url: URL, key: SymmetricKey) throws -> Note {
        let data     = try Data(contentsOf: url)
        let envelope = try JSONDecoder().decode(EncryptedNoteEnvelope.self, from: data)

        let payload: NotePayload
        do {
            let decrypted = try CryptoEngine.decrypt(combined: envelope.encryptedPayload, key: key)
            payload = try JSONDecoder().decode(NotePayload.self, from: decrypted)
        } catch CryptoError.tamperedData {
            throw NoteStoreError.tamperedNote(id: envelope.id)
        }

        return Note(
            id: UUID(uuidString: envelope.id) ?? UUID(),
            title: payload.title,
            content: payload.content,
            color: NoteColor(rawValue: envelope.colorRaw) ?? .yellow,
            position: CGPoint(x: envelope.positionX, y: envelope.positionY),
            size: CGSize(width: envelope.width, height: envelope.height)
        )
    }

    private func encrypt(note: Note, key: SymmetricKey) throws -> EncryptedNoteEnvelope {
        let payload     = NotePayload(title: note.title, content: note.content)
        let payloadData = try JSONEncoder().encode(payload)
        let encrypted   = try CryptoEngine.encrypt(plaintext: payloadData, key: key)
        let salt        = KeyDerivation.generateSalt()

        return EncryptedNoteEnvelope(
            id: note.id.uuidString,
            encryptedPayload: encrypted,
            salt: salt,
            createdAt: note.createdAt,
            updatedAt: Date(),
            positionX: note.position.x,
            positionY: note.position.y,
            width: note.size.width,
            height: note.size.height,
            colorRaw: note.color.rawValue
        )
    }

    private func createDirectoryIfNeeded() {
        try? fm.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: notesDirectory.path)
    }
}

extension Notification.Name {
    static let tamperedNotesDetected = Notification.Name("TokenDepot.tamperedNotesDetected")
}
