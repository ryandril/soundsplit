import CoreAudio
import Foundation

/// UID prefix for the private aggregate devices SoundSplit creates, so they never show up in its own list.
let aggregateUIDPrefix = "io.github.ryandril.soundsplit.route."

struct OutputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transport: UInt32

    var symbol: String {
        let lowered = name.lowercased()
        if lowered.contains("airpods") || lowered.contains("headphone") || lowered.contains("buds") {
            return "headphones"
        }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "hifispeaker"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        default: return "speaker.wave.2"
        }
    }

    static func all() -> [OutputDevice] {
        AudioObjectID.system.readIDs(.init(kAudioHardwarePropertyDevices)).compactMap { id in
            guard id.channelCount(kAudioObjectPropertyScopeOutput) > 0,
                  id.read(.init(kAudioDevicePropertyIsHidden), default: UInt32(0)) == 0,
                  let uid = id.readString(.init(kAudioDevicePropertyDeviceUID)),
                  !uid.hasPrefix(aggregateUIDPrefix) else { return nil }
            return OutputDevice(
                id: id,
                uid: uid,
                name: id.readString(.init(kAudioObjectPropertyName)) ?? "Unknown device",
                transport: id.read(.init(kAudioDevicePropertyTransportType), default: UInt32(0))
            )
        }
    }

    static func defaultOutputUID() -> String? {
        let id = AudioObjectID.system.read(.init(kAudioHardwarePropertyDefaultOutputDevice), default: AudioObjectID(kAudioObjectUnknown))
        return id == kAudioObjectUnknown ? nil : id.readString(.init(kAudioDevicePropertyDeviceUID))
    }
}

/// The device's own volume control. Some outputs (HDMI, some USB DACs) have none; those get a software gain instead.
enum HardwareVolume {
    private static func address(_ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        .init(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, element)
    }

    private static func elements(_ device: AudioObjectID) -> [AudioObjectPropertyElement] {
        if device.isSettable(address(kAudioObjectPropertyElementMain)) { return [kAudioObjectPropertyElementMain] }
        return [1, 2].filter { device.isSettable(address($0)) }
    }

    static func get(_ device: AudioObjectID) -> Float? {
        let elements = elements(device)
        guard !elements.isEmpty else { return nil }
        let total = elements.reduce(Float32(0)) { $0 + device.read(address($1), default: Float32(0)) }
        return total / Float(elements.count)
    }

    static func set(_ device: AudioObjectID, _ value: Float) {
        for element in elements(device) {
            device.write(address(element), Float32(value))
        }
    }
}
