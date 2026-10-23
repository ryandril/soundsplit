import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.permission == .denied {
                PermissionBanner()
                Divider()
            }

            SectionLabel("Outputs")
            VStack(spacing: 14) {
                ForEach(store.devices) { DeviceRow(device: $0) }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)

            Divider()

            SectionLabel("Apps")
            if store.apps.isEmpty {
                Text("Apps show up here once they make a sound.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.apps) { AppRow(app: $0) }
                    }
                    .padding(.horizontal, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 300)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
            }

            if let problem = store.problem {
                Divider()
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(14)
            }

            Divider()
            Footer()
        }
        .frame(width: 320)
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }
}

private struct DeviceRow: View {
    @EnvironmentObject private var store: Store
    let device: OutputDevice

    private var volume: Binding<Double> {
        Binding(
            get: { Double(store.volumes[device.uid] ?? 1) },
            set: { store.setVolume(Float($0), for: device) }
        )
    }

    var body: some View {
        let playing = store.apps(playingOn: device)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: device.symbol)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name).lineLimit(1)
                    Text(subtitle(playing: playing))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(Int((volume.wrappedValue * 100).rounded()))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .trailing)
            }
            Slider(value: volume, in: 0...1)
                .controlSize(.small)
                .padding(.leading, 26)
                .accessibilityLabel("\(device.name) volume")
        }
    }
}

private extension DeviceRow {
    func subtitle(playing: [AudioApp]) -> String {
        let names = playing.map(\.name).joined(separator: ", ")
        if device.uid == store.defaultUID {
            return names.isEmpty ? "System output" : "System output · \(names)"
        }
        return names.isEmpty ? "Silent" : names
    }
}

private struct PermissionBanner: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "lock")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("Audio access is off")
                Text("Turn on SoundSplit under System Audio Recording Only, or moved apps stay silent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Open Settings") { AudioPermission.openSettings() }
                .controlSize(.small)
        }
        .padding(14)
    }
}

private struct AppRow: View {
    @EnvironmentObject private var store: Store
    let app: AudioApp

    private var selection: Binding<String> {
        Binding(
            get: { store.assignments[app.id] ?? "" },
            set: { store.assign(app, to: $0.isEmpty ? nil : $0) }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 20, height: 20)
            Text(app.name).lineLimit(1)
            Circle()
                .fill(.green)
                .frame(width: 5, height: 5)
                .opacity(app.isPlaying ? 1 : 0)
                // State change seen a few times a minute: a short fade, no movement.
                .animation(.easeOut(duration: 0.15), value: app.isPlaying)
                .accessibilityLabel(app.isPlaying ? "Playing" : "")
            Spacer(minLength: 8)
            Picker("Output for \(app.name)", selection: selection) {
                Text("System output").tag("")
                Divider()
                ForEach(store.devices) { Text($0.name).tag($0.uid) }
                if let saved = store.assignments[app.id], !store.isConnected(saved) {
                    Text("\(store.name(ofDevice: saved)) (off)").tag(saved)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 136)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }
}

private struct Footer: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack {
            Toggle("Open at login", isOn: Binding(
                get: { store.launchesAtLogin },
                set: { store.launchesAtLogin = $0 }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
