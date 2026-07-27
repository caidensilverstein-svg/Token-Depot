import SwiftUI

@main
struct TokenDepotApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var auth = AuthManager.shared

    var body: some Scene {
        // No main window — app is menubar-only + floating note windows
        Settings {
            EmptyView()
        }
    }
}
