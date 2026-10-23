import AppKit

/// "System Audio Recording Only" access. macOS prompts by itself the first time a route starts; if the person
/// says no, taps run but stay silent, so the app needs to notice that and point to Settings.
/// There is no public API for the check; the TCC call below is looked up at runtime and assumed granted if missing.
enum AudioPermission {
    enum Status { case granted, denied, unknown }

    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int

    static var status: Status {
        guard let symbol = dlsym(tcc, "TCCAccessPreflight") else { return .granted }
        switch unsafeBitCast(symbol, to: Preflight.self)(service, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .unknown
        }
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
    }
}
