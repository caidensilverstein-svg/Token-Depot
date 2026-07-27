import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {

    private var unlockWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var menuBar: MenuBarController?
    private var authCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        menuBar = MenuBarController.shared

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

        authCancellable = AuthManager.shared.$isUnlocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] unlocked in
                if unlocked { self?.onUnlocked() }
            }

        if !AuthManager.shared.isSetup {
            showSetupFlow()
        } else {
            showUnlockScreen()
        }
    }

    // MARK: — Screen Lock

    @objc private func screenDidLock() {
        MenuBarController.shared.closeAllWindows()
        NoteStore.shared.clearMemory()
        AuthManager.shared.lock()
        showUnlockScreen()
    }

    // MARK: — Auth Flow

    private func onUnlocked() {
        unlockWindow?.close()
        unlockWindow = nil
        setupWindow?.close()
        setupWindow = nil

        guard let key = AuthManager.shared.activeKey() else { return }
        try? NoteStore.shared.loadAll(key: key)

        if NoteStore.shared.notes.isEmpty {
            let note = Note()
            try? NoteStore.shared.save(note: note, key: key)
        }

        MenuBarController.shared.openNotes(NoteStore.shared.notes)
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
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        unlockWindow = window
    }

    private func showSetupFlow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 580),
            // Add .closable so the red X works
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
            // If they close setup without finishing, quit — app is unusable without credentials
            NSApp.terminate(nil)
        }
        if window === unlockWindow {
            unlockWindow = nil
        }
    }
}
