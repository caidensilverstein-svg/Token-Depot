import AppKit
import SwiftUI

/// A floating, borderless sticky note window.
class StickyNoteWindow: NSWindow {

    let noteId: UUID
    private let vm: NoteViewModel
    private var hostingView: NSHostingView<StickyNoteView>?

    init(note: Note) {
        self.noteId = note.id
        self.vm = NoteViewModel(note: note)

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
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        minSize = NSSize(width: 160, height: 120)
        sharingType = .none
    }

    private func setContent() {
        let view = StickyNoteView(vm: vm, window: self)
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        contentView = hosting
        hostingView = hosting
    }

    // MARK: — Save position on move

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        vm.position = CGPoint(x: frame.origin.x, y: frame.origin.y)
        vm.save()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        vm.size = CGSize(width: frameRect.width, height: frameRect.height)
    }
}
