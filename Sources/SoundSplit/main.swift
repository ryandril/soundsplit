import AppKit

// Plain AppKit entry point. A SwiftUI `App` needs at least one scene, and its placeholder
// Settings window kept appearing whenever the app was activated; a menu bar app has no window.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { NSApplication.shared.run() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: Store?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = Store()
        self.store = store
        menuBar = MenuBarController(store: store)
    }

    // Opening SoundSplit from Finder or Spotlight while it runs shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        menuBar?.open()
        return false
    }
}
