import SwiftUI
import AppKit

// MARK: — NoteViewModel

final class NoteViewModel: ObservableObject {
    @Published var content: String
    @Published var color: NoteColor

    let id: UUID
    let createdAt: Date
    var position: CGPoint
    var size: CGSize
    var title: String

    init(note: Note) {
        self.id        = note.id
        self.title     = note.title
        self.content   = note.content
        self.color     = note.color
        self.position  = note.position
        self.size      = note.size
        self.createdAt = note.createdAt
    }

    var asNote: Note {
        Note(id: id, title: title, content: content, color: color, position: position, size: size)
    }

    func save() {
        guard let key = AuthManager.shared.activeKey() else { return }
        try? NoteStore.shared.save(note: asNote, key: key)
    }
}

// MARK: — StickyNoteView

struct StickyNoteView: View {

    @ObservedObject var vm: NoteViewModel
    // Use a closure to close instead of weak window ref — avoids dangling pointer crash
    var onClose: (() -> Void)?

    @State private var showDeleteConfirm = false
    @State private var deletePassword = ""
    @State private var deleteError = false
    @FocusState private var editorFocused: Bool

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
        // Force focus into editor on appear
        .onAppear { editorFocused = true }
        .alert("Delete Note", isPresented: $showDeleteConfirm) {
            SecureField("Enter master password", text: $deletePassword)
            Button("Delete", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) {
                deletePassword = ""
                deleteError = false
            }
        } message: {
            Text(deleteError
                 ? "Wrong password. Try again."
                 : "Enter your master password to permanently delete this note.")
        }
    }

    // MARK: — Title Bar

    private var titleBar: some View {
        HStack(spacing: 6) {
            ForEach(NoteColor.allCases, id: \.self) { color in
                Circle()
                    .fill(colorForNote(color))
                    .frame(width: 10, height: 10)
                    .onTapGesture { vm.color = color; vm.save() }
            }
            Spacer()
            Button { showDeleteConfirm = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        // Clicking title bar area makes window key so editor gets focus
        .contentShape(Rectangle())
        .onTapGesture { editorFocused = true }
    }

    // MARK: — Content

    private var contentArea: some View {
        TextEditor(text: $vm.content)
            .font(.system(size: 13))
            .foregroundColor(.black.opacity(0.85))
            .background(Color.clear)
            .scrollContentBackground(.hidden)
            .focused($editorFocused)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .onChange(of: vm.content) { _ in vm.save() }
    }

    // MARK: — Delete

    private func confirmDelete() {
        guard let salt       = try? KeychainManager.load(key: "td.passwordSalt"),
              let storedHash = try? KeychainManager.load(key: "td.passwordHash"),
              let candidate  = try? KeyDerivation.hashForStorage(value: deletePassword, salt: salt)
        else { deleteError = true; deletePassword = ""; return }

        guard KeyDerivation.constantTimeEqual(storedHash, candidate) else {
            deleteError = true; deletePassword = ""; return
        }

        deletePassword = ""
        deleteError    = false

        try? NoteStore.shared.delete(note: vm.asNote)
        DispatchQueue.main.async { onClose?() }
    }

    // MARK: — Colors

    private var noteColor: Color { colorForNote(vm.color) }

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
