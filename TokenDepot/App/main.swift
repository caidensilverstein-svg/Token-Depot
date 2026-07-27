import AppKit

// Pure AppKit entry point — no SwiftUI App lifecycle fighting us
// This gives full control over activation policy and menubar behavior
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Set accessory BEFORE run — this is the correct order
// Doing it inside applicationDidFinishLaunching is too late on some macOS versions
app.setActivationPolicy(.accessory)

app.run()
