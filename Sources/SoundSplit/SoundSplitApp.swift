import SwiftUI

@main
struct SoundSplitApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra("SoundSplit", systemImage: "hifispeaker.2") {
            ContentView().environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}
