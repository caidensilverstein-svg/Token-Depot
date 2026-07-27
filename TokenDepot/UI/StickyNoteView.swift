import SwiftUI
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

// MARK: — SecureNSTextView (NSTextView subclass with paste override)

final class SecureNSTextView: NSTextView {

    // Override paste to force plain text — strips rich text/formatting
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let str = pb.string(forType: .string) {
            insertText(str, replacementRange: selectedRange())
        } else if let str = pb.string(forType: .URL) {
            insertText(str, replacementRange: selectedRange())
        }
    }

    // Also handle pasteAsPlainText
    override func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }

    // Block AX entirely at the NSTextView level
    override func isAccessibilityElement() -> Bool { return false }
    override func accessibilityRole() -> NSAccessibility.Role? { return .unknown }
}

// MARK: — SecureTextEditor (NSViewRepresentable — AX tree fully opted out)

/// Replaces SwiftUI TextEditor. NSTextView with accessibility disabled so
/// osascript / AXIsProcessTrusted scrapers cannot read note content.
struct SecureTextEditor: NSViewRepresentable {

    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false

        let contentSize = scrollView.contentSize
        let textView = SecureNSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView

        // Appearance
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = NSColor.black.withAlphaComponent(0.85)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        // Explicitly allow paste operations
        textView.importsGraphics = false
        textView.usesFindPanel = false

        // Scroll view appearance
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false

        // SECURITY: opt entire view tree out of accessibility
        // Prevents osascript / AX API from reading note content
        textView.setAccessibilityElement(false)
        textView.setAccessibilityRole(.unknown)
        textView.setAccessibilityLabel("")
        scrollView.setAccessibilityElement(false)
        scrollView.setAccessibilityRole(.unknown)

        textView.delegate = context.coordinator
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only update if changed to avoid cursor jumping
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SecureTextEditor
        init(_ parent: SecureTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        // Force plain text paste — strips formatting, always works
        @objc func paste(_ sender: Any?) {
            guard let textView = sender as? NSTextView else { return }
            let pb = NSPasteboard.general
            if let str = pb.string(forType: .string) {
                textView.insertText(str, replacementRange: textView.selectedRange())
            }
        }
    }
}

// MARK: — StickyNoteView

struct StickyNoteView: View {

    @ObservedObject var vm: NoteViewModel
    var onClose: (() -> Void)?

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
                SecureTextEditor(text: $vm.content)
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
                    .onTapGesture {
                        vm.color = color
                        vm.saveImmediate()
                    }
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
        .contentShape(Rectangle())
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
        vm.saveImmediate()
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
