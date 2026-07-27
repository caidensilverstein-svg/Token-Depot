import SwiftUI

// @main removed — entry point is main.swift for pure AppKit control
// SwiftUI scenes not used; all windows managed by AppDelegate directly
struct TokenDepotApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
