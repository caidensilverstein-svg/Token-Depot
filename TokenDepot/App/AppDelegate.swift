import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {

    private var unlockWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var authCancellable: AnyCancellable?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildEditMenu()
        _ = MenuBarController.shared

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenDidLock),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showUnlockScreen),
            name: .showUnlockScreen,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTamperedNotes(_:)),
            name: .tamperedNotesDetected,
            object: nil
        )

        authCancellable = AuthManager.shared.$isUnlocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] unlocked in
                if unlocked { self?.onUnlocked() }
            }

        setupGlobalHotkeys()

        if !AuthManager.shared.isSetup {
            showSetupFlow()
        } else {
            showUnlockScreen()
        }
    }

    // MARK: — Global Hotkeys

    private func setupGlobalHotkeys() {
        // ⌘⌥N — new note (works system-wide)
        // ⌘⌥Q — quit
        // ⌘⌥L — lock
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains([.command, .option]) else { return }
            switch event.charactersIgnoringModifiers {
            case "n": self?.newNote()
            case "q": self?.quit()
            case "l": self?.lock()
            default: break
            }
        }

        // Also catch when app IS focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains([.command, .option]) else { return event }
            switch event.charactersIgnoringModifiers {
            case "n": self?.newNote(); return nil
            case "q": self?.quit(); return nil
            case "l": self?.lock(); return nil
            default: return event
            }
        }
    }

    @objc private func newNote() {
        guard AuthManager.shared.isUnlocked else { return }
        guard let key = AuthManager.shared.activeKey() else { return }
        let note = Note(position: NoteStore.shared.nextNotePosition())
        try? NoteStore.shared.save(note: note, key: key)
        MenuBarController.shared.openNote(note)
    }

    @objc private func quit() {
        NoteStore.shared.clearMemory()
        AuthManager.shared.lock()
        NSApp.terminate(nil)
    }

    @objc private func lock() {
        MenuBarController.shared.closeAllWindows()
        NoteStore.shared.clearMemory()
        AuthManager.shared.lock()
        showUnlockScreen()
    }

    // MARK: — Quit

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        NoteStore.shared.clearMemory()
        AuthManager.shared.lock()
        return .terminateNow
    }

    // MARK: — Screen Lock

    @objc private func screenDidLock() {
        MenuBarController.shared.closeAllWindows()
        NoteStore.shared.clearMemory()
        AuthManager.shared.lock()
        showUnlockScreen()
    }

    // MARK: — Tamper Alert

    @objc private func handleTamperedNotes(_ notification: Notification) {
        guard let ids = notification.object as? [String], !ids.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Tampered Notes Detected"
        alert.informativeText = "\(ids.count) note file(s) failed authentication and were skipped.\n\nAffected IDs:\n\(ids.joined(separator: "\n"))"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: — Auth Flow

    private func onUnlocked() {
        unlockWindow?.close()
        unlockWindow = nil
        setupWindow?.close()
        setupWindow = nil

        guard let key = AuthManager.shared.activeKey() else { return }

        Task.detached(priority: .userInitiated) {
            try? NoteStore.shared.loadAll(key: key)
            await MainActor.run {
                if NoteStore.shared.notes.isEmpty {
                    let note = Note(position: NoteStore.shared.nextNotePosition())
                    try? NoteStore.shared.save(note: note, key: key)
                }
                MenuBarController.shared.openNotes(NoteStore.shared.notes)
            }
        }
    }

    // MARK: — Windows

    @objc func showUnlockScreen() {
        guard unlockWindow == nil else {
            unlockWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "TokenDepot"
        window.center()
        window.contentView = NSHostingView(rootView: UnlockView())
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        unlockWindow = window
    }

    private func showSetupFlow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up TokenDepot"
        window.center()
        window.contentView = NSHostingView(rootView: SetupView())
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        setupWindow = window
    }

    deinit {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === setupWindow {
            setupWindow = nil
            NSApp.terminate(nil)
        }
        if window === unlockWindow {
            unlockWindow = nil
        }
    }
}

extension AppDelegate {
    func buildEditMenu() {
        let mainMenu = NSMenu()

        // App menu (required)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit TokenDepot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        // Edit menu — required for cmd shortcuts to route correctly
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut",        action: #selector(NSText.cut(_:)),       keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy",       action: #selector(NSText.copy(_:)),      keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste",      action: #selector(NSText.paste(_:)),     keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenu.addItem(NSMenuItem(title: "Undo",       action: #selector(UndoManager.undo),     keyEquivalent: "z"))
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }
}
