import AppKit
import SwiftUI

/// Manages the menubar icon and note window lifecycle.
final class MenuBarController: NSObject {

    static let shared = MenuBarController()

    private var statusItem: NSStatusItem!
    private(set) var noteWindows: [UUID: StickyNoteWindow] = [:]

    private override init() {
        super.init()
        DispatchQueue.main.async { self.setupMenuBar() }
    }

    // MARK: — Menubar Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true

        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "lock.doc.fill", accessibilityDescription: "TokenDepot") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "TD"
            }
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let newItem = NSMenuItem(title: "New Note", action: #selector(newNote), keyEquivalent: "n")
        newItem.keyEquivalentModifierMask = .command
        newItem.target = self
        menu.addItem(newItem)

        menu.addItem(.separator())

        let showItem = NSMenuItem(title: "Show All Notes", action: #selector(showAll), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let hideItem = NSMenuItem(title: "Hide All Notes", action: #selector(hideAll), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        menu.addItem(.separator())

        let lockItem = NSMenuItem(title: "Lock TokenDepot", action: #selector(lockApp), keyEquivalent: "l")
        lockItem.keyEquivalentModifierMask = .command
        lockItem.target = self
        menu.addItem(lockItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit TokenDepot", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: — Note Window Management

    func openNotes(_ notes: [Note]) {
        for note in notes { openNote(note) }
    }

    func openNote(_ note: Note) {
        if let existing = noteWindows[note.id] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = StickyNoteWindow(note: note)
        window.delegate = self
        noteWindows[note.id] = window
        window.makeKeyAndOrderFront(nil)
    }

    func closeAllWindows() {
        let ids = Array(noteWindows.keys)
        for id in ids { noteWindows[id]?.close() }
        noteWindows.removeAll()
    }

    // MARK: — Actions

    @objc private func newNote() {
        guard let key = AuthManager.shared.activeKey() else { return }
        // Stagger new note position so they don't all pile up
        let pos  = NoteStore.shared.nextNotePosition()
        let note = Note(position: pos)
        try? NoteStore.shared.save(note: note, key: key)
        openNote(note)
    }

    @objc private func showAll() {
        noteWindows.values.forEach { $0.makeKeyAndOrderFront(nil) }
    }

    @objc private func hideAll() {
        noteWindows.values.forEach { $0.orderOut(nil) }
    }

    @objc private func lockApp() {
        closeAllWindows()
        NoteStore.shared.clearMemory()
        AuthManager.shared.lock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .showUnlockScreen, object: nil)
        }
    }

    @objc private func quitApp() {
        NoteStore.shared.clearMemory()
        AuthManager.shared.lock()
        NSApp.terminate(nil)
    }
}

// MARK: — NSWindowDelegate

extension MenuBarController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? StickyNoteWindow else { return }
        noteWindows.removeValue(forKey: window.noteId)
    }
}

extension Notification.Name {
    static let showUnlockScreen = Notification.Name("TokenDepot.showUnlockScreen")
}
