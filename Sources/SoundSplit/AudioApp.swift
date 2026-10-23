import AppKit
import CoreAudio

/// A regular (Dock) app together with every Core Audio process that plays sound for it.
/// Browsers play through helper processes, so one app usually owns several.
struct AudioApp: Identifiable, Equatable {
    let id: String // bundle identifier
    let name: String
    let pid: pid_t
    var processes: [AudioObjectID]
    var isPlaying: Bool

    var icon: NSImage {
        NSRunningApplication(processIdentifier: pid)?.icon ?? NSWorkspace.shared.icon(for: .application)
    }

    static func current() -> [AudioApp] {
        let regular = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.processIdentifier != getpid()
        }
        let byPID = Dictionary(regular.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })

        var apps: [String: AudioApp] = [:]
        for process in AudioObjectID.system.readIDs(.init(kAudioHardwarePropertyProcessObjectList)) {
            let pid = process.read(.init(kAudioProcessPropertyPID), default: pid_t(-1))
            guard pid > 0 else { continue }
            let bundleID = process.readString(.init(kAudioProcessPropertyBundleID)) ?? ""
            guard let owner = owner(of: pid, bundleID: bundleID, byPID: byPID, regular: regular),
                  let ownerID = owner.bundleIdentifier else { continue }

            let playing = process.read(.init(kAudioProcessPropertyIsRunningOutput), default: UInt32(0)) != 0
            var app = apps[ownerID] ?? AudioApp(id: ownerID, name: owner.localizedName ?? ownerID,
                                               pid: owner.processIdentifier, processes: [], isPlaying: false)
            app.processes.append(process)
            app.isPlaying = app.isPlaying || playing
            apps[ownerID] = app
        }
        // Alphabetical, never by "playing": rows that reorder on their own are hard to click.
        return apps.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func owner(of pid: pid_t, bundleID: String,
                              byPID: [pid_t: NSRunningApplication],
                              regular: [NSRunningApplication]) -> NSRunningApplication? {
        if let app = byPID[pid] { return app }
        if let responsiblePID, let app = byPID[responsiblePID(pid)] { return app }
        guard !bundleID.isEmpty else { return nil }
        return regular.first { bundleID.hasPrefix($0.bundleIdentifier! + ".") }
    }

    /// `responsibility_get_pid_for_pid` maps an XPC helper (e.g. Safari's WebKit audio process) to the app that launched it.
    /// It is not public API, so look it up at runtime and fall back to bundle-ID matching without it.
    private typealias ResponsiblePID = @convention(c) (pid_t) -> pid_t
    private static let responsiblePID: ResponsiblePID? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsiblePID.self)
    }()
}
