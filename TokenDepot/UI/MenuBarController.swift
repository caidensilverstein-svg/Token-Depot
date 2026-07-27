import AppKit
import SwiftUI

final class MenuBarController: NSObject {

    static let shared = MenuBarController()

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private(set) var noteWindows: [UUID: StickyNoteWindow] = [:]

    private override init() {
        super.init()
        setupMenuBar()
    }

    // MARK: — Setup

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
            // Use action instead of attaching menu directly —
            // direct menu attachment breaks after a window steals key focus
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        buildMenu()
    }

    private func buildMenu() {
        menu = NSMenu()
        menu.autoenablesItems = false

        func item(_ title: String, action: Selector, key: String = "", mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = self
            i.isEnabled = true
            return i
        }

        menu.addItem(item("New Note",        action: #selector(newNote),  key: "n"))
        menu.addItem(.separator())
        menu.addItem(item("Show All Notes",  action: #selector(showAll),  key: ""))
        menu.addItem(item("Hide All Notes",  action: #selector(hideAll),  key: ""))
        menu.addItem(.separator())
        menu.addItem(item("Lock TokenDepot", action: #selector(lockApp),  key: "l"))
        menu.addItem(.separator())
        menu.addItem(item("Quit TokenDepot", action: #selector(quitApp),  key: "q"))
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        // Manually pop the menu at the button location
        // This works regardless of which window is currently key
        guard let button = statusItem.button else { return }
        menu.popUp(
            positioning: menu.item(at: 0),
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
    }

    // MARK: — Note Windows

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
        let note = Note(position: NoteStore.shared.nextNotePosition())
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
