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
        sharingType = .none
        acceptsMouseMovedEvents = true
    }

    private func setContent() {
        let view = StickyNoteView(vm: vm, onClose: { [weak self] in
            self?.close()
        })
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        hosting.setAccessibilityElement(false)
        hosting.setAccessibilityRole(.unknown)
        contentView = hosting
    }

    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Activate app and make key BEFORE passing event so text view gets focus
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)

        super.mouseDown(with: event)

        // Force first responder to the text view after click
        DispatchQueue.main.async { [weak self] in
            self?.makeFirstResponderToTextView()
        }
    }

    func makeFirstResponderToTextView() {
        // Walk the view hierarchy to find SecureNSTextView and make it first responder
        func findTextView(in view: NSView) -> SecureNSTextView? {
            if let tv = view as? SecureNSTextView { return tv }
            for sub in view.subviews {
                if let found = findTextView(in: sub) { return found }
            }
            return nil
        }
        if let tv = contentView.flatMap({ findTextView(in: $0) }) {
            makeFirstResponder(tv)
        }
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
