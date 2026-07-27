import AppKit
import Combine

// MARK: — NoteViewModel

final class NoteViewModel: ObservableObject {
    @Published var content: String
    @Published var color: NoteColor

    let id: UUID
    let createdAt: Date
    var position: CGPoint
    var size: CGSize
    var title: String

    private var saveCancellable: AnyCancellable?

    init(note: Note) {
        self.id        = note.id
        self.title     = note.title
        self.content   = note.content
        self.color     = note.color
        self.position  = note.position
        self.size      = note.size
        self.createdAt = note.createdAt

        saveCancellable = $content
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] _ in self?.save() }
    }

    var asNote: Note {
        Note(id: id, title: title, content: content, color: color, position: position, size: size)
    }

    func save() {
        guard let key = AuthManager.shared.activeKey() else { return }
        try? NoteStore.shared.save(note: asNote, key: key)
    }

    func saveImmediate() {
        saveCancellable?.cancel()
        save()
    }
}

// MARK: — SecureNSTextView

final class SecureNSTextView: NSTextView {

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let str = pb.string(forType: .string) {
            insertText(str, replacementRange: selectedRange())
        }
    }

    override func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }

    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityRole() -> NSAccessibility.Role? { .unknown }
}
