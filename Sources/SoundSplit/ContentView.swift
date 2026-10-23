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
            VStack(spacing: 10) {
                ForEach(store.devices) { DeviceRow(device: $0) }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

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
                    VStack(spacing: 0) {
                        ForEach(store.apps) { AppRow(app: $0) }
                    }
                    .padding(.horizontal, 5)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 300)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 5)
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
        .frame(width: 300)
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        // Same weight and size as the section titles in the system's own menus.
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: device.symbol)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(device.name).lineLimit(1)
                    Text(subtitle(playing: playing))
                        .font(.system(size: 11))
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

/// Reads like a menu item: the whole row is the button, highlighted on hover, and opens the output menu.
private struct AppRow: View {
    @EnvironmentObject private var store: Store
    let app: AudioApp
    // Not @State: on this SDK it's a macro that ships only with full Xcode, and the project builds with the Command Line Tools.
    @StateObject private var hover = Hover()

    private var selection: Binding<String> {
        Binding(
            get: { store.assignments[app.id] ?? "" },
            set: { store.assign(app, to: $0.isEmpty ? nil : $0) }
        )
    }

    private var current: String {
        guard let uid = store.assignments[app.id] else { return "System output" }
        return store.isConnected(uid) ? store.name(ofDevice: uid) : "\(store.name(ofDevice: uid)) (off)"
    }

    var body: some View {
        Menu {
            Picker("Output for \(app.name)", selection: selection) {
                Text("System output").tag("")
                Divider()
                ForEach(store.devices) { Text($0.name).tag($0.uid) }
                if let saved = store.assignments[app.id], !store.isConnected(saved) {
                    Text("\(store.name(ofDevice: saved)) (off)").tag(saved)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(app.name).lineLimit(1)
                Circle()
                    .fill(.green)
                    .frame(width: 5, height: 5)
                    .opacity(app.isPlaying ? 1 : 0)
                    // State change seen a few times a minute: a short fade, no movement.
                    .animation(.easeOut(duration: 0.15), value: app.isPlaying)
                    .accessibilityLabel(app.isPlaying ? "Playing" : "")
                Spacer(minLength: 8)
                Text(current)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            // Menus highlight instantly; no hover animation.
            .background(hover.on ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hover.on = $0 }
    }
}

private final class Hover: ObservableObject {
    @Published var on = false
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
