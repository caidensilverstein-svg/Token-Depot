import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {

    private var unlockWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var authCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Init menubar FIRST before activation policy change
        _ = MenuBarController.shared

        // Accessory = no dock icon, menubar only
        NSApp.setActivationPolicy(.accessory)

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

        // Watch auth state via Combine
        authCancellable = AuthManager.shared.$isUnlocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] unlocked in
                if unlocked { self?.onUnlocked() }
            }

        // Boot
        if !AuthManager.shared.isSetup {
            showSetupFlow()
        } else {
            showUnlockScreen()
        }
    }

    // MARK: — ⌘Q to quit

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
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

        // Load notes on background thread — KDF already done, this is just disk I/O
        Task.detached(priority: .userInitiated) {
            try? NoteStore.shared.loadAll(key: key)
            await MainActor.run {
                if NoteStore.shared.notes.isEmpty {
                    let note = Note()
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
