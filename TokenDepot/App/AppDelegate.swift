import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {

    private var unlockWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var authCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menubar init — synchronous, main thread, before anything else
        _ = MenuBarController.shared

        // Screen lock observer
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

        // Tamper detection alert
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTamperedNotes(_:)),
            name: .tamperedNotesDetected,
            object: nil
        )

        // Watch auth state
        authCancellable = AuthManager.shared.$isUnlocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] unlocked in
                if unlocked { self?.onUnlocked() }
            }

        // Boot flow
        if !AuthManager.shared.isSetup {
            showSetupFlow()
        } else {
            showUnlockScreen()
        }
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
        alert.informativeText = "\(ids.count) note file(s) failed authentication and were skipped. This may indicate tampering or file corruption.\n\nAffected IDs:\n\(ids.joined(separator: "\n"))"
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
                    let pos  = NoteStore.shared.nextNotePosition()
                    let note = Note(position: pos)
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
}

// MARK: — NSWindowDelegate

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
