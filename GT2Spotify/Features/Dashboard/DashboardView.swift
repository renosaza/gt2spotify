import MediaPlayer
import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @Environment(\.openURL) private var openURL

    init(viewModel: DashboardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Spotify authorization") {
                    LabeledContent("Configured", value: viewModel.isConfigured ? "Yes" : "No")
                    LabeledContent("Token in Keychain", value: viewModel.isAuthorized ? "Yes" : "No")
                    Button("Connect Spotify") { viewModel.connectSpotify() }
                        .disabled(viewModel.isBusy || !viewModel.isConfigured)
                    Button("Open Spotify") {
                        if let url = URL(string: "spotify://") { openURL(url) }
                    }
                }

                Section("Playback") {
                    if let playback = viewModel.playback {
                        Text(playback.track).font(.headline)
                        Text(playback.artist).foregroundStyle(.secondary)
                        LabeledContent("State", value: playback.isPlaying ? "Playing" : "Paused")
                        LabeledContent("Device", value: playback.deviceName ?? "Unknown")
                        LabeledContent("Volume", value: playback.volumePercent.map { "\($0)%" } ?? "Unavailable")
                        LabeledContent("Remote volume", value: playback.supportsVolume ? "Supported" : "Unavailable")
                    } else {
                        Text("No playback snapshot loaded")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button { viewModel.perform(.previous) } label: { Image(systemName: "backward.fill") }
                        Spacer()
                        Button { viewModel.perform(.play) } label: { Image(systemName: "play.fill") }
                        Spacer()
                        Button { viewModel.perform(.pause) } label: { Image(systemName: "pause.fill") }
                        Spacer()
                        Button { viewModel.perform(.next) } label: { Image(systemName: "forward.fill") }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isBusy || !viewModel.isAuthorized)
                }

                Section("Volume") {
                    if viewModel.supportsSpotifyVolumeControl {
                        HStack {
                            Button { viewModel.perform(.volumeDown) } label: { Image(systemName: "speaker.minus.fill") }
                            Slider(value: $viewModel.volume, in: 0...100, step: 1)
                            Button { viewModel.perform(.volumeUp) } label: { Image(systemName: "speaker.plus.fill") }
                        }
                        Button("Set volume to \(Int(viewModel.volume))%") { viewModel.setAbsoluteVolume() }
                            .disabled(viewModel.isBusy || !viewModel.isAuthorized)
                        Text("This slider sends a Spotify Web API command to the active Connect device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if viewModel.shouldUseSystemVolumeControl {
                        Text("The active Spotify device does not accept remote volume commands. Use the native iOS system volume control below.")
                            .font(.callout)
                        SystemVolumeControl()
                            .frame(minHeight: 44)
                    } else {
                        Text("Refresh playback and devices to determine which volume control is available.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Devices") {
                    if viewModel.devices.isEmpty {
                        Text("No devices loaded").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(viewModel.devices.enumerated()), id: \.offset) { _, device in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                    Text(device.type).font(.caption).foregroundStyle(.secondary)
                                    Text(device.supportsVolume ? "Remote volume supported" : "Use local/system volume")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if device.isActive { Image(systemName: "checkmark.circle.fill") }
                            }
                        }
                    }
                }

                Section("Diagnostics") {
                    Text(viewModel.statusMessage)
                    Button("Refresh playback and devices") { viewModel.refresh() }
                        .disabled(viewModel.isBusy || !viewModel.isAuthorized)
                }

                Section("Huawei") {
                    Text("Not implemented in Phase 1. This build does not scan, pair, bond, reset, or write to a watch.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("GT2Spotify")
            .overlay {
                if viewModel.isBusy { ProgressView().controlSize(.large) }
            }
        }
    }
}

private struct SystemVolumeControl: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.showsVolumeSlider = true
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
