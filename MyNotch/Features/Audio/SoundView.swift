import SwiftUI

/// The Sound tab: the current output and its volume on the left, every output as a card on the right.
struct SoundView: View {
    private let audio = AudioOutputService.shared

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(.white.opacity(0.03))
            .overlay {
                HStack(spacing: 12) {
                    currentPanel.frame(width: 190)
                    Divider().overlay(.white.opacity(0.12))
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 6) {
                            ForEach(audio.devices) { device in
                                DeviceCard(device: device, isCurrent: device.id == audio.currentID) {
                                    audio.select(device)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
                .padding(10)
            }
            .onAppear { audio.refresh() }
    }

    private var currentPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: audio.current?.symbol ?? "speaker.wave.2")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.accentColor))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Playing through")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(audio.current?.name ?? "No output")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            volumeRow
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var volumeRow: some View {
        if audio.hasVolumeControl {
            let level = audio.isMuted ? 0 : audio.volume
            HStack(spacing: 6) {
                Button { audio.setMuted(!audio.isMuted) } label: {
                    Image(systemName: speakerSymbol(level))
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 18)
                        .foregroundStyle(.white.opacity(0.8))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .help(audio.isMuted ? "Unmute" : "Mute")
                VolumeSlider(value: level) { audio.setVolume($0) }
                Text("\(Int(level * 100))")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 20, alignment: .trailing)
            }
        } else {
            Label("Volume is set on the device", systemImage: "speaker.slash")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func speakerSymbol(_ level: Float) -> String {
        if level == 0 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

private struct DeviceCard: View {
    let device: AudioOutputDevice
    let isCurrent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: device.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isCurrent ? Color.accentColor : .white.opacity(0.1)))
                    .foregroundStyle(.white)
                Text(device.name)
                    .font(.system(size: 10, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(isCurrent ? 1 : 0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.top, 10)
            .padding(.horizontal, 6)
            .frame(width: 96)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(isCurrent ? 0.1 : (hovering ? 0.08 : 0.04)))
            )
            .overlay(alignment: .topTrailing) {
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                        .padding(5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isCurrent ? "\(device.name) (playing here)" : "Play sound through \(device.name)")
    }
}

/// Thin capsule slider matching the media scrubber.
private struct VolumeSlider: View {
    let value: Float
    let onChange: (Float) -> Void
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
            }
            .frame(height: dragging ? 6 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        dragging = true
                        onChange(Float(min(max(drag.location.x / geo.size.width, 0), 1)))
                    }
                    .onEnded { _ in dragging = false }
            )
            .animation(.easeOut(duration: 0.1), value: dragging)
        }
        .frame(height: 14)
    }
}
