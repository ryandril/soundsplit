import AppKit
import CoreAudio
import ServiceManagement

@MainActor
final class Store: ObservableObject {
    @Published private(set) var devices: [OutputDevice] = []
    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var defaultUID: String?
    @Published private(set) var volumes: [String: Float] = [:]
    @Published private(set) var problem: String?
    @Published private(set) var permission = AudioPermission.status

    /// App bundle ID → device UID. Missing means "follow the system output".
    @Published private(set) var assignments: [String: String]
    /// Device UID → last known name, so a remembered speaker that is switched off still has a label.
    private var knownNames: [String: String]
    /// Device UID → gain, for outputs without their own volume control.
    private var softGains: [String: Float]
    private var hardwareVolumeUIDs: Set<String> = []

    private lazy var router = Router { [weak self] error in self?.problem = error }
    private let defaults = UserDefaults.standard
    private var timer: Timer?

    init() {
        assignments = defaults.dictionary(forKey: "assignments") as? [String: String] ?? [:]
        knownNames = defaults.dictionary(forKey: "knownNames") as? [String: String] ?? [:]
        softGains = defaults.dictionary(forKey: "softGains") as? [String: Float] ?? [:]

        refreshDevices()
        refreshApps()

        let system = AudioObjectID.system
        system.onChange(.init(kAudioHardwarePropertyDevices)) { [weak self] in self?.refreshDevices() }
        system.onChange(.init(kAudioHardwarePropertyDefaultOutputDevice)) { [weak self] in self?.refreshDevices() }
        system.onChange(.init(kAudioHardwarePropertyProcessObjectList)) { [weak self] in self?.refreshApps() }

        // "Is this app playing right now" and outside volume changes have no cheap listener; a light poll is enough.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshApps()
                self?.refreshVolumes()
                self?.refreshPermission()
            }
        }

        #if DEBUG
        Snapshot.runIfRequested(store: self)
        #endif

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.router.stopAll() }
        }
    }

    // MARK: Reading the system

    private func refreshDevices() {
        let current = OutputDevice.all()
        if current != devices { devices = current }
        defaultUID = OutputDevice.defaultOutputUID()
        hardwareVolumeUIDs = Set(current.filter { HardwareVolume.get($0.id) != nil }.map(\.uid))
        for device in current where knownNames[device.uid] != device.name {
            knownNames[device.uid] = device.name
            defaults.set(knownNames, forKey: "knownNames")
        }
        refreshVolumes()
        applyRoutes()
    }

    private func refreshApps() {
        let current = AudioApp.current()
        if current != apps { apps = current }
        applyRoutes()
    }

    private func refreshVolumes() {
        var next: [String: Float] = [:]
        for device in devices {
            next[device.uid] = HardwareVolume.get(device.id) ?? softGains[device.uid] ?? 1
        }
        if next != volumes { volumes = next }
    }

    private func refreshPermission() {
        let current = AudioPermission.status
        guard current != permission else { return }
        permission = current
        // Taps made before access was granted stay silent; start them again.
        if current == .granted {
            router.stopAll()
            applyRoutes()
        }
    }

    // MARK: User actions


    func assign(_ app: AudioApp, to uid: String?) {
        assignments[app.id] = uid
        defaults.set(assignments, forKey: "assignments")
        applyRoutes()
    }

    func setVolume(_ value: Float, for device: OutputDevice) {
        volumes[device.uid] = value
        if hardwareVolumeUIDs.contains(device.uid) {
            HardwareVolume.set(device.id, value)
        } else {
            softGains[device.uid] = value
            defaults.set(softGains, forKey: "softGains")
            applyRoutes()
        }
    }

    // MARK: Derived

    func name(ofDevice uid: String) -> String {
        devices.first { $0.uid == uid }?.name ?? knownNames[uid] ?? "Unknown device"
    }

    func isConnected(_ uid: String) -> Bool {
        devices.contains { $0.uid == uid }
    }

    /// Where an app's sound actually comes out right now.
    func effectiveDevice(for app: AudioApp) -> String? {
        if let uid = assignments[app.id], isConnected(uid) { return uid }
        return defaultUID
    }

    func apps(playingOn device: OutputDevice) -> [AudioApp] {
        apps.filter { $0.isPlaying && effectiveDevice(for: $0) == device.uid }
    }

    private func applyRoutes() {
        var plan: [String: RouteTarget] = [:]
        for app in apps {
            guard let uid = assignments[app.id], isConnected(uid) else { continue }
            let gain = hardwareVolumeUIDs.contains(uid) ? 1 : softGains[uid] ?? 1
            // Sent to the device the system already plays on: nothing to move, unless soft gain needs applying.
            if uid == defaultUID && gain == 1 { continue }
            plan[uid, default: RouteTarget(processes: [], gain: gain)].processes.formUnion(app.processes)
        }
        router.apply(plan)
    }

    // MARK: Launch at login

    var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }
}
