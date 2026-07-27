import AppKit
import SwiftUI

/// A floating, borderless sticky note window.
class StickyNoteWindow: NSWindow {

    let noteId: UUID
    let vm: NoteViewModel

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

        // Block screenshot APIs
        sharingType = .none

        acceptsMouseMovedEvents = true
    }

    private func setContent() {
        let view = StickyNoteView(vm: vm, onClose: { [weak self] in
            self?.close()
        })
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true

        // Gemini concern #5: opt out of accessibility tree
        // Prevents AXIsProcessTrusted() scraping of decrypted note content
        hosting.setAccessibilityElement(false)
        hosting.setAccessibilityRole(.unknown)

        contentView = hosting
    }

    // MARK: — Key window (required for TextEditor focus in borderless window)

    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }

    override func mouseDown(with event: NSEvent) {
        makeKey()
        NSApp.activate(ignoringOtherApps: true)
        super.mouseDown(with: event)
    }

    // MARK: — Save position/size on move/resize

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
