import AppKit
import SwiftUI

/// The menu bar icon and the panel under it.
/// SwiftUI's MenuBarExtra window floats a gap below the bar in its own window style; this panel instead behaves like
/// the system's Sound and Wi-Fi menus: pinned under the icon, menu material, icon highlighted while open,
/// closed by clicking anywhere else or pressing Escape. It opens instantly: it's used many times a day.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel: MenuPanel
    private let host: SizingHostingView
    private var monitors: [Any] = []

    init(store: Store) {
        host = SizingHostingView(rootView: AnyView(ContentView().environmentObject(store)))
        panel = MenuPanel(content: host)
        super.init()
        // Keep the top edge pinned under the icon when the app list grows or shrinks.
        host.onSizeChange = { [weak self] in
            guard let self, isOpen else { return }
            position()
        }

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hifispeaker.2", accessibilityDescription: "SoundSplit")
            button.target = self
            button.action = #selector(toggle)
            // System menus react on press, not release.
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        #if DEBUG
        // `--open-panel` opens the panel at launch and prints its frames, to check sizing without clicking.
        if CommandLine.arguments.contains("--open-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                open()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                    FileHandle.standardError.write("panel \(panel.frame) content \(host.frame)\n".data(using: .utf8)!)
                }
            }
        }
        #endif
    }

    private var isOpen = false

    @objc private func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        position()
        panel.makeKeyAndOrderFront(nil)
        // Highlight after this click finishes: highlighting during the button's own click handling makes it swallow the next click.
        DispatchQueue.main.async { [weak self] in
            guard let self, isOpen else { return }
            statusItem.button?.highlight(true)
        }

        // Clicks in other apps. Clicks on our own icon never reach a global monitor, so they only go through toggle().
        let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.close() }
            return nil
        }
        monitors = [outside, escape].compactMap { $0 }
    }

    private func close() {
        guard isOpen else { return }
        isOpen = false
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private func position() {
        guard let button = statusItem.button, let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let icon = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        // Ask the SwiftUI content, not the glass around it: the glass view doesn't report its content's size.
        let size = host.fittingSize
        let visible = screen.visibleFrame
        // Left-aligned with the icon like a menu, nudged back on screen near the right edge.
        let x = min(max(icon.minX, visible.minX + 8), visible.maxX - size.width - 8)
        let y = icon.minY - size.height - 4
        panel.setFrame(NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height), display: true)
    }
}

/// Reports when the SwiftUI content changes size, so the panel can follow.
final class SizingHostingView: NSHostingView<AnyView> {
    var onSizeChange: (@MainActor () -> Void)?

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        sizingOptions = [.intrinsicContentSize]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onSizeChange?() }
    }
}

final class MenuPanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false

        let radius: CGFloat = 12
        let chrome: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = radius
            content.autoresizingMask = [.width, .height]
            glass.contentView = content
            chrome = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .menu
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = radius
            material.layer?.masksToBounds = true
            content.translatesAutoresizingMaskIntoConstraints = false
            material.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: material.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: material.trailingAnchor),
                content.topAnchor.constraint(equalTo: material.topAnchor),
                content.bottomAnchor.constraint(equalTo: material.bottomAnchor),
            ])
            chrome = material
        }
        contentView = chrome
    }

    // Needed for Escape and for the menus inside to take keyboard input.
    override var canBecomeKey: Bool { true }
}
