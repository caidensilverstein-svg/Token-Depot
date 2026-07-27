import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

    private var unlockWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from dock — menubar only app
        NSApp.setActivationPolicy(.accessory)

        // Init menubar
        menuBar = MenuBarController.shared

        // Listen for lock/unlock notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showUnlockScreen),
            name: .showUnlockScreen,
            object: nil
        )

        // Listen for screen lock (display sleep / screensaver)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenDidLock),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )

        // Auth state observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(authStateChanged),
            name: .init("AuthManager.isUnlockedChanged"),
            object: nil
        )

        // Boot
        if !AuthManager.shared.isSetup {
            showSetupFlow()
        } else {
            showUnlockScreen()
        }
    }

    // MARK: — Screen Lock

    @objc private func screenDidLock() {
        // Auto-lock on screen lock
        MenuBarController.shared.closeAllWindows()
        NoteStore.shared.clearMemory()
        AuthManager.shared.lock()
        showUnlockScreen()
    }

    // MARK: — Auth Flow

    @objc private func authStateChanged() {
        if AuthManager.shared.isUnlocked {
            onUnlocked()
        }
    }

    private func onUnlocked() {
        unlockWindow?.close()
        unlockWindow = nil

        guard let key = AuthManager.shared.activeKey() else { return }
        try? NoteStore.shared.loadAll(key: key)
        MenuBarController.shared.openNotes(NoteStore.shared.notes)
    }

    // MARK: — Windows

    @objc func showUnlockScreen() {
        guard unlockWindow == nil else {
            unlockWindow?.makeKeyAndOrderFront(nil)
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
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up TokenDepot"
        window.center()
        window.contentView = NSHostingView(rootView: SetupView())
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        setupWindow = window
    }
}
