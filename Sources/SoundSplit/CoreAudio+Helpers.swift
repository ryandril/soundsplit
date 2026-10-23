import CoreAudio
import Foundation

struct CoreAudioError: Error, CustomStringConvertible {
    let status: OSStatus
    let what: String
    var description: String { "\(what) failed (OSStatus \(status))" }
}

func check(_ status: OSStatus, _ what: String) throws {
    guard status == noErr else { throw CoreAudioError(status: status, what: what) }
}

extension AudioObjectPropertyAddress {
    init(_ selector: AudioObjectPropertySelector,
         _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
         _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) {
        self.init(mSelector: selector, mScope: scope, mElement: element)
    }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    func isSettable(_ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(self, &address),
              AudioObjectIsPropertySettable(self, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    func read<T: BitwiseCopyable>(_ address: AudioObjectPropertyAddress, default fallback: T) -> T {
        var address = address
        var value = fallback
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &value)
        return status == noErr ? value : fallback
    }

    func readString(_ address: AudioObjectPropertyAddress) -> String? {
        var address = address
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }

    func readIDs(_ address: AudioObjectPropertyAddress) -> [AudioObjectID] {
        var address = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    @discardableResult
    func write<T: BitwiseCopyable>(_ address: AudioObjectPropertyAddress, _ value: T) -> OSStatus {
        var address = address
        var value = value
        return AudioObjectSetPropertyData(self, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
    }

    func channelCount(_ scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// Calls `handler` on the main queue whenever the property changes. Lives as long as the app.
    func onChange(_ address: AudioObjectPropertyAddress, _ handler: @escaping () -> Void) {
        var address = address
        AudioObjectAddPropertyListenerBlock(self, &address, .main) { _, _ in handler() }
    }
}
