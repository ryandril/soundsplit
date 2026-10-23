#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: `SoundSplit --snapshot out.png` renders the live panel to a PNG, for checking layout without a click.
@MainActor
enum Snapshot {
    static func runIfRequested(store: Store) {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--snapshot"), flag + 1 < args.count else { return }
        let path = args[flag + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let dark = args.contains("--dark")
            let view = NSHostingView(rootView: ContentView()
                .environmentObject(store)
                .environment(\.colorScheme, dark ? .dark : .light)
                .background(Color(nsColor: dark ? NSColor(white: 0.16, alpha: 1) : .white)))
            view.frame.size = view.fittingSize
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.backgroundColor = .windowBackgroundColor
            window.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                exit(0)
            }
        }
    }
}
#endif
