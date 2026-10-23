import SwiftUI

@main
struct SoundSplitApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    // The UI is the menu bar panel; SwiftUI still needs one scene.
    var body: some Scene {
        Settings { EmptyView() }
    }
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
}
