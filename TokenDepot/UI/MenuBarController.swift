import AppKit
import SwiftUI

/// Manages the menubar icon and note window lifecycle.
final class MenuBarController: NSObject {

    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private(set) var noteWindows: [UUID: StickyNoteWindow] = [:]

    private override init() {
        super.init()
        setupMenuBar()
    }

    // MARK: — Menubar Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "lock.doc", accessibilityDescription: "TokenDepot")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "New Note",       action: #selector(newNote),  keyEquivalent: "n"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Show All Notes", action: #selector(showAll),  keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hide All Notes", action: #selector(hideAll),  keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Lock",           action: #selector(lockApp),  keyEquivalent: "l"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit",           action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
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
        // Snapshot keys first to avoid mutating dict while iterating via delegate
        let ids = Array(noteWindows.keys)
        for id in ids {
            noteWindows[id]?.close()
        }
        noteWindows.removeAll()
    }

    // MARK: — Actions

    @objc private func newNote() {
        guard let key = AuthManager.shared.activeKey() else { return }
        let note = Note()
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
        // Close all windows first, then lock, then show unlock screen
        closeAllWindows()
        NoteStore.shared.clearMemory()
        AuthManager.shared.lock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .showUnlockScreen, object: nil)
        }
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
