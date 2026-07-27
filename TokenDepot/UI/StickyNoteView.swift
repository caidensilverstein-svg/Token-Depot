import SwiftUI
import AppKit

struct StickyNoteView: View {

    @State var note: Note
    weak var window: StickyNoteWindow?

    @State private var showDeleteConfirm = false
    @State private var deletePassword = ""
    @State private var deleteError = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(noteColor)
                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)

            VStack(spacing: 0) {
                titleBar
                Divider().opacity(0.3)
                contentArea
            }
        }
        .privacySensitive()
        .alert("Delete Note", isPresented: $showDeleteConfirm) {
            SecureField("Enter master password", text: $deletePassword)
            Button("Delete", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) {
                deletePassword = ""
                deleteError = false
            }
        } message: {
            Text(deleteError ? "Wrong password. Try again." : "Enter your master password to permanently delete this note.")
        }
    }

    // MARK: — Title Bar

    private var titleBar: some View {
        HStack(spacing: 6) {
            ForEach(NoteColor.allCases, id: \.self) { color in
                Circle()
                    .fill(colorForNote(color))
                    .frame(width: 10, height: 10)
                    .onTapGesture { changeColor(color) }
            }
            Spacer()
            Button {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: — Content

    private var contentArea: some View {
        TextEditor(text: $note.content)
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(.black.opacity(0.85))
            .background(Color.clear)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .onChange(of: note.content) { _ in
                saveNote()
            }
    }

    // MARK: — Actions

    private func saveNote() {
        guard let key = AuthManager.shared.activeKey() else { return }
        try? NoteStore.shared.save(note: note, key: key)
    }

    private func changeColor(_ color: NoteColor) {
        note = Note(
            id: note.id,
            title: note.title,
            content: note.content,
            color: color,
            position: note.position,
            size: note.size
        )
        saveNote()
    }

    private func confirmDelete() {
        // Verify password by re-deriving and comparing hash — don't re-unlock the session
        guard let salt = try? KeychainManager.load(key: "td.passwordSalt"),
              let storedHash = try? KeychainManager.load(key: "td.passwordHash"),
              let candidateHash = try? KeyDerivation.hashForStorage(value: deletePassword, salt: salt) else {
            deleteError = true
            deletePassword = ""
            return
        }

        guard KeyDerivation.constantTimeEqual(storedHash, candidateHash) else {
            deleteError = true
            deletePassword = ""
            return
        }

        deletePassword = ""
        deleteError = false
        try? NoteStore.shared.delete(note: note)
        window?.close()
    }

    // MARK: — Colors

    private var noteColor: Color { colorForNote(note.color) }

    private func colorForNote(_ color: NoteColor) -> Color {
        switch color {
        case .yellow: return Color(red: 1.0,  green: 0.96, blue: 0.6)
        case .blue:   return Color(red: 0.75, green: 0.88, blue: 1.0)
        case .green:  return Color(red: 0.8,  green: 0.97, blue: 0.75)
        case .pink:   return Color(red: 1.0,  green: 0.82, blue: 0.88)
        case .gray:   return Color(red: 0.9,  green: 0.9,  blue: 0.92)
        }
    }
}
