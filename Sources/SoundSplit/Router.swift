import CoreAudio
import Foundation

/// Read on the audio thread, written on the main thread. A single aligned Float, so a torn read can't happen.
final class Gain: @unchecked Sendable {
    var value: Float
    init(_ value: Float) { self.value = value }
}

/// Moves a set of processes to one output device:
///   1. a process tap captures their audio and mutes it at the source,
///   2. a private aggregate device pairs that tap with the target output,
///   3. an IO callback copies the tap's samples into the output's buffers.
/// Everything is private to this process, so macOS cleans it up even if the app crashes.
final class DeviceRoute {
    let deviceUID: String
    let processes: Set<AudioObjectID>
    let gain: Gain

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    init(deviceUID: String, processes: Set<AudioObjectID>, gain: Float) throws {
        self.deviceUID = deviceUID
        self.processes = processes
        self.gain = Gain(gain)
        do {
            try start()
        } catch {
            stop()
            throw error
        }
    }

    private func start() throws {
        let tap = CATapDescription(stereoMixdownOfProcesses: Array(processes))
        tap.uuid = UUID()
        tap.name = "SoundSplit"
        tap.muteBehavior = .mutedWhenTapped
        tap.isPrivate = true
        try check(AudioHardwareCreateProcessTap(tap, &tapID), "Creating the audio tap")

        let format = tapID.read(.init(kAudioTapPropertyFormat), default: AudioStreamBasicDescription())
        guard format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mChannelsPerFrame > 0 else {
            throw CoreAudioError(status: -1, what: "Reading the tap format")
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SoundSplit",
            kAudioAggregateDeviceUIDKey: aggregateUIDPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tap.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID), "Creating the aggregate device")

        let channels = Int(format.mChannelsPerFrame)
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        let tapBuffers = interleaved ? 1 : channels
        let gain = self.gain

        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, _ in
            render(input: input, output: output, channels: channels, interleaved: interleaved,
                   tapBuffers: tapBuffers, gain: gain.value)
        }, "Creating the audio callback")

        disableDeviceInputs()
        try check(AudioDeviceStart(aggregateID, procID), "Starting playback")
    }

    /// The aggregate also inherits the target's own inputs (a Bluetooth speaker's microphone, say).
    /// Opening those would drop a Bluetooth device into low-quality headset mode, so switch them off; the tap is always last.
    private func disableDeviceInputs() {
        guard let procID else { return }
        var address = AudioObjectPropertyAddress(kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(aggregateID, &address, 0, nil, &size) == noErr else { return }

        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
        defer { raw.deallocate() }
        raw.storeBytes(of: unsafeBitCast(procID, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        guard AudioObjectGetPropertyData(aggregateID, &address, 0, nil, &size, raw) == noErr else { return }

        let streamCount = Int(raw.load(fromByteOffset: 8, as: UInt32.self))
        guard streamCount > 1 else { return }
        let flags = raw.advanced(by: 12).bindMemory(to: UInt32.self, capacity: streamCount)
        for stream in 0..<(streamCount - 1) { flags[stream] = 0 }
        AudioObjectSetPropertyData(aggregateID, &address, 0, nil, size, raw)
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }
}

/// Runs on the real-time audio thread: no allocation, no locks.
/// The tap's buffers come last in `input`. Output channels 1 and 2 get left and right; any extra channels stay silent.
private func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>,
                    channels: Int, interleaved: Bool, tapBuffers: Int, gain: Float) {
    let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
    let outputs = UnsafeMutableAudioBufferListPointer(output)
    let first = inputs.count - tapBuffers

    var outChannel = 0
    var totalOut = 0
    for buffer in outputs { totalOut += Int(buffer.mNumberChannels) }

    for buffer in outputs {
        let outChannels = Int(buffer.mNumberChannels)
        guard let outData = buffer.mData?.assumingMemoryBound(to: Float.self), outChannels > 0 else { continue }
        let outFrames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * outChannels)
        outData.update(repeating: 0, count: outFrames * outChannels)
        guard first >= 0 else { outChannel += outChannels; continue }

        for c in 0..<outChannels {
            let channel = outChannel + c
            for frame in 0..<outFrames {
                let sample: Float
                if totalOut == 1 && channels >= 2 {
                    sample = (tapSample(inputs, first, 0, frame, channels, interleaved)
                            + tapSample(inputs, first, 1, frame, channels, interleaved)) * 0.5
                } else if channel < channels {
                    sample = tapSample(inputs, first, channel, frame, channels, interleaved)
                } else if channels == 1 && channel < 2 {
                    sample = tapSample(inputs, first, 0, frame, channels, interleaved)
                } else {
                    continue
                }
                outData[frame * outChannels + c] = sample * gain
            }
        }
        outChannel += outChannels
    }
}

@inline(__always)
private func tapSample(_ inputs: UnsafeMutableAudioBufferListPointer, _ first: Int, _ channel: Int,
                       _ frame: Int, _ channels: Int, _ interleaved: Bool) -> Float {
    let buffer = inputs[interleaved ? first : first + channel]
    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return 0 }
    let index = interleaved ? frame * channels + channel : frame
    return index < Int(buffer.mDataByteSize) / MemoryLayout<Float>.size ? data[index] : 0
}

struct RouteTarget: Equatable {
    var processes: Set<AudioObjectID>
    var gain: Float
}

/// Keeps one route per target device and rebuilds a route only when the processes sent to it change.
/// Core Audio calls here can block (the first one waits on the macOS permission prompt), so they run on their own queue.
final class Router {
    private let queue = DispatchQueue(label: "SoundSplit.router")
    private var lastPlan: [String: RouteTarget]?
    private let onError: (String?) -> Void

    // Only touched on `queue`.
    private var routes: [String: DeviceRoute] = [:]
    /// Targets that failed to start, so a broken device isn't retried every refresh. Cleared when its plan changes.
    private var failed: [String: Set<AudioObjectID>] = [:]

    /// `onError` is called on the main queue with the latest failure, or nil once everything runs.
    init(onError: @escaping (String?) -> Void) {
        self.onError = onError
    }

    /// `plan` maps a device UID to what it should play. Call from the main queue.
    func apply(_ plan: [String: RouteTarget]) {
        guard plan != lastPlan else { return }
        lastPlan = plan
        queue.async { [self] in
            for (uid, route) in routes where plan[uid]?.processes != route.processes {
                route.stop()
                routes[uid] = nil
            }
            failed = failed.filter { plan[$0.key]?.processes == $0.value }
            var error: String?
            for (uid, target) in plan where failed[uid] == nil {
                if let route = routes[uid] {
                    route.gain.value = target.gain
                    continue
                }
                do {
                    routes[uid] = try DeviceRoute(deviceUID: uid, processes: target.processes, gain: target.gain)
                } catch let failure {
                    failed[uid] = target.processes
                    error = "\(failure)"
                }
            }
            if !failed.isEmpty, error == nil { return }
            DispatchQueue.main.async { [onError] in onError(error) }
        }
    }

    /// Tears every route down, synchronously so it finishes before the app quits.
    func stopAll() {
        lastPlan = nil
        queue.sync {
            routes.values.forEach { $0.stop() }
            routes = [:]
            failed = [:]
        }
    }
}
