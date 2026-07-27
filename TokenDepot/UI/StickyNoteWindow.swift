import AppKit
import SwiftUI

/// A floating, borderless sticky note window.
/// Stays above normal windows but below fullscreen apps.
class StickyNoteWindow: NSWindow {

    var note: Note
    private var hostingView: NSHostingView<StickyNoteView>?

    init(note: Note) {
        self.note = note

        super.init(
            contentRect: NSRect(
                x: note.position.x,
                y: note.position.y,
                width: note.size.width,
                height: note.size.height
            ),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        configure()
        setContent()
    }

    private func configure() {
        // Float above normal windows, below fullscreen
        level = .floating

        // No title bar, transparent background
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Allow moving by dragging the window background
        isMovableByWindowBackground = true

        // Stay visible across spaces
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Minimum size
        minSize = NSSize(width: 160, height: 120)

        // Privacy — blur content when app is not active / screen captured
        sharingType = .none
    }

    private func setContent() {
        let view = StickyNoteView(note: note, window: self)
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        contentView = hosting
        hostingView = hosting
    }

    func updateNote(_ updated: Note) {
        self.note = updated
        let view = StickyNoteView(note: updated, window: self)
        hostingView?.rootView = view
    }

    // MARK: — Privacy: blank content when backgrounded

    override func resignMain() {
        super.resignMain()
        // .privacySensitive() on the SwiftUI side handles screenshot blocking
    }

    // MARK: — Save position on move

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        savePosition()
    }

    private func savePosition() {
        guard let key = AuthManager.shared.activeKey() else { return }
        var updated = note
        updated = Note(
            id: note.id,
            title: note.title,
            content: note.content,
            color: note.color,
            position: CGPoint(x: frame.origin.x, y: frame.origin.y),
            size: CGSize(width: frame.width, height: frame.height)
        )
        try? NoteStore.shared.save(note: updated, key: key)
    }
}
