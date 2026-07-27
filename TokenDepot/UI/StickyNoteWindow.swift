import AppKit
import Combine

/// Pure AppKit sticky note window — no SwiftUI hosting view in the responder chain.
/// This ensures NSTextView gets first responder correctly and paste works.
class StickyNoteWindow: NSWindow {

    let noteId: UUID
    let vm: NoteViewModel

    private var textView: SecureNSTextView!
    private var contentObserver: AnyCancellable?

    init(note: Note) {
        self.noteId = note.id
        self.vm = NoteViewModel(note: note)

        super.init(
            contentRect: NSRect(x: note.position.x, y: note.position.y,
                                width: note.size.width, height: note.size.height),
            // .titled gives proper keyboard/focus handling; we hide the titlebar visually
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        configure()
        buildView()
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
        // Hide title bar while keeping .titled style for proper keyboard routing
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func buildView() {
        // Root view — the note background
        let root = NoteBackgroundView(color: noteNSColor(vm.color))
        root.autoresizingMask = [.width, .height]
        root.frame = NSRect(origin: .zero, size: frame.size)

        // Title bar
        let titleBar = buildTitleBar()
        titleBar.frame = NSRect(x: 0, y: root.frame.height - 30, width: root.frame.width, height: 30)
        titleBar.autoresizingMask = [.width, .minYMargin]
        root.addSubview(titleBar)

        // Divider
        let divider = NSBox()
        divider.boxType = .separator
        divider.frame = NSRect(x: 0, y: root.frame.height - 31, width: root.frame.width, height: 1)
        divider.autoresizingMask = [.width, .minYMargin]
        root.addSubview(divider)

        // Text view
        let scrollView = SecureNSTextView.scrollableTextView()
        scrollView.frame = NSRect(x: 0, y: 0, width: root.frame.width, height: root.frame.height - 31)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false

        textView = scrollView.documentView as? SecureNSTextView
        textView.font = .systemFont(ofSize: 13)
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
        textView.string = vm.content
        textView.delegate = self

        textView.setAccessibilityElement(false)
        textView.setAccessibilityRole(.unknown)
        scrollView.setAccessibilityElement(false)

        root.addSubview(scrollView)
        contentView = root

        // Sync vm.content changes back to text view (e.g. from load)
        contentObserver = vm.$content
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newContent in
                guard let self = self else { return }
                if self.textView.string != newContent {
                    self.textView.string = newContent
                }
            }
    }

    private func buildTitleBar() -> NSView {
        let barWidth = frame.width
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: barWidth, height: 30))
        bar.wantsLayer = true
        bar.autoresizingMask = [.width]

        // Color dots — left side
        var x: CGFloat = 10
        for color in NoteColor.allCases {
            let dot = ColorDotButton(noteColor: color) { [weak self] selected in
                self?.vm.color = selected
                self?.vm.saveImmediate()
                (self?.contentView as? NoteBackgroundView)?.setColor(self?.noteNSColor(selected) ?? .yellow)
            }
            dot.frame = NSRect(x: x, y: 10, width: 10, height: 10)
            bar.addSubview(dot)
            x += 16
        }

        // Paste button at x=barWidth-56 (clipboard icon)
        let pasteBtn = NSButton(frame: NSRect(x: barWidth - 56, y: 5, width: 20, height: 20))
        pasteBtn.bezelStyle = .inline
        pasteBtn.isBordered = false
        pasteBtn.title = "📋"
        pasteBtn.font = .systemFont(ofSize: 13)
        pasteBtn.autoresizingMask = [.minXMargin]
        pasteBtn.target = self
        pasteBtn.action = #selector(pasteFromClipboard)
        bar.addSubview(pasteBtn)

        // Delete button at x=barWidth-28 (x mark)
        let deleteBtn = NSButton(frame: NSRect(x: barWidth - 28, y: 5, width: 20, height: 20))
        deleteBtn.bezelStyle = .inline
        deleteBtn.isBordered = false
        deleteBtn.title = "✕"
        deleteBtn.font = .systemFont(ofSize: 11)
        deleteBtn.contentTintColor = NSColor.black.withAlphaComponent(0.6)
        deleteBtn.autoresizingMask = [.minXMargin]
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteNote)
        bar.addSubview(deleteBtn)

        return bar
    }

    @objc private func pasteFromClipboard() {
        let pb = NSPasteboard.general
        if let str = pb.string(forType: .string) {
            textView.insertText(str, replacementRange: textView.selectedRange())
        }
    }

    @objc private func deleteNote() {
        // Show password prompt
        let alert = NSAlert()
        alert.messageText = "Delete Note"
        alert.informativeText = "Enter your master password to permanently delete this note."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let password = input.stringValue
        guard let salt      = try? KeychainManager.load(key: "td.passwordSalt"),
              let stored    = try? KeychainManager.load(key: "td.passwordHash"),
              let candidate = try? KeyDerivation.hashForStorage(value: password, salt: salt),
              KeyDerivation.constantTimeEqual(stored, candidate)
        else {
            let err = NSAlert()
            err.messageText = "Wrong password"
            err.runModal()
            return
        }

        vm.saveImmediate()
        try? NoteStore.shared.delete(note: vm.asNote)
        close()
    }

    // MARK: — Key window

    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        // Give text view first responder after window is key
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.makeFirstResponder(self.textView)
        }
    }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        super.mouseDown(with: event)
    }

    // Route cmd shortcuts directly through the responder chain to the text view
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command else { return super.performKeyEquivalent(with: event) }

        // Use NSApp.sendAction so it goes through the proper responder chain
        NSLog("[TD] performKeyEquivalent called: %@, firstResponder: %@", event.charactersIgnoringModifiers ?? "nil", String(describing: firstResponder))
        switch event.charactersIgnoringModifiers {
        case "v":
            NSApp.sendAction(#selector(NSText.paste(_:)), to: firstResponder, from: self)
            return true
        case "c":
            NSApp.sendAction(#selector(NSText.copy(_:)), to: firstResponder, from: self)
            return true
        case "x":
            NSApp.sendAction(#selector(NSText.cut(_:)), to: firstResponder, from: self)
            return true
        case "a":
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: firstResponder, from: self)
            return true
        case "z":
            NSApp.sendAction(Selector(("undo:")), to: firstResponder, from: self)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    // MARK: — Position/size

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        vm.position = CGPoint(x: frame.origin.x, y: frame.origin.y)
        vm.save()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        vm.size = CGSize(width: frameRect.width, height: frameRect.height)
    }

    // MARK: — Color helpers

    private func noteNSColor(_ color: NoteColor) -> NSColor {
        switch color {
        case .yellow: return NSColor(red: 1.0,  green: 0.96, blue: 0.6,  alpha: 1)
        case .blue:   return NSColor(red: 0.75, green: 0.88, blue: 1.0,  alpha: 1)
        case .green:  return NSColor(red: 0.8,  green: 0.97, blue: 0.75, alpha: 1)
        case .pink:   return NSColor(red: 1.0,  green: 0.82, blue: 0.88, alpha: 1)
        case .gray:   return NSColor(red: 0.9,  green: 0.9,  blue: 0.92, alpha: 1)
        }
    }
}

// MARK: — NSTextViewDelegate

extension StickyNoteWindow: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        vm.content = tv.string
    }
}

// MARK: — Helper views

class NoteBackgroundView: NSView {
    private var bgColor: NSColor

    init(color: NSColor) {
        self.bgColor = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 4
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setColor(_ color: NSColor) {
        bgColor = color
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        bgColor.setFill()
        bounds.fill()
    }
}

class ColorDotButton: NSButton {
    private let noteColor: NoteColor
    private let onSelect: (NoteColor) -> Void

    init(noteColor: NoteColor, onSelect: @escaping (NoteColor) -> Void) {
        self.noteColor = noteColor
        self.onSelect = onSelect
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.masksToBounds = true
        isBordered = false
        bezelStyle = .inline
        title = ""
        target = self
        action = #selector(tapped)
        setColor()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setColor() {
        switch noteColor {
        case .yellow: layer?.backgroundColor = NSColor(red: 1.0,  green: 0.96, blue: 0.6,  alpha: 1).cgColor
        case .blue:   layer?.backgroundColor = NSColor(red: 0.75, green: 0.88, blue: 1.0,  alpha: 1).cgColor
        case .green:  layer?.backgroundColor = NSColor(red: 0.8,  green: 0.97, blue: 0.75, alpha: 1).cgColor
        case .pink:   layer?.backgroundColor = NSColor(red: 1.0,  green: 0.82, blue: 0.88, alpha: 1).cgColor
        case .gray:   layer?.backgroundColor = NSColor(red: 0.9,  green: 0.9,  blue: 0.92, alpha: 1).cgColor
        }
    }

    @objc private func tapped() { onSelect(noteColor) }
}
