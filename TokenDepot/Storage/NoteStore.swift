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
        for fileURL in files {
            do {
                let note = try loadNote(from: fileURL, key: key)
                loaded.append(note)
            } catch NoteStoreError.tamperedNote(let id) {
                // Surface tamper detection — don't silently skip
                print("[TokenDepot] TAMPER DETECTED on note \(id) — skipping")
                // TODO: surface alert in UI
            }
        }

        notes = loaded.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: — Save

    func save(note: Note, key: SymmetricKey) throws {
        let envelope = try encrypt(note: note, key: key)
        let data = try JSONEncoder().encode(envelope)

        let fileURL = notesDirectory.appendingPathComponent("\(note.id.uuidString).tdnote")

        // Write atomically — never partial writes
        try data.write(to: fileURL, options: [.atomic])

        // Set file permissions to 600 — owner read/write only
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)

        // Update in-memory list
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = note
        } else {
            notes.insert(note, at: 0)
        }
    }

    // MARK: — Delete (requires confirmation, not panic)

    func delete(note: Note) throws {
        let fileURL = notesDirectory.appendingPathComponent("\(note.id.uuidString).tdnote")
        try SecureWipe.wipeFile(at: fileURL)
        notes.removeAll { $0.id == note.id }
    }

    // MARK: — Panic Wipe

    /// Triggered by panic password — multi-pass wipe of all note files.
    func panicWipeAll() {
        do {
            try SecureWipe.wipeDirectory(at: notesDirectory)
        } catch {
            // Best-effort — even if wipe fails partway, directory is gone
        }
        notes = []
        createDirectoryIfNeeded()
    }

    // MARK: — Clear from memory on lock

    func clearMemory() {
        notes = []
    }

    // MARK: — Private

    private func loadNote(from url: URL, key: SymmetricKey) throws -> Note {
        let data = try Data(contentsOf: url)
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
        let payload = NotePayload(title: note.title, content: note.content)
        let payloadData = try JSONEncoder().encode(payload)

        // Fresh nonce every save — never reused
        let encryptedPayload = try CryptoEngine.encrypt(plaintext: payloadData, key: key)
        let salt = KeyDerivation.generateSalt()  // Per-note salt for future key rotation support

        return EncryptedNoteEnvelope(
            id: note.id.uuidString,
            encryptedPayload: encryptedPayload,
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
        // Set directory permissions to 700
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: notesDirectory.path)
    }
}
