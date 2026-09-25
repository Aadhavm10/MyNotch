import SwiftUI

struct ArtworkView: View {
    let image: NSImage?
    var cornerRadius: CGFloat = 10

    /// Takes exactly the size it's given and center-crops the image into it, so non-square
    /// art (e.g. 16:9 YouTube thumbnails) can't grow past its box.
    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note").foregroundStyle(.white.opacity(0.4))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct MediaWidget: View {
    let model: NowPlayingModel

    var body: some View {
        if model.hasTrack {
            HStack(spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.title ?? "")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(model.artist ?? model.album ?? "")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .lineLimit(1)
                        Spacer(minLength: 4)
                        VisualizerView(isPlaying: model.isPlaying, tint: model.tint, barCount: 5)
                            .frame(width: 20, height: 14)
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    ScrubberView(model: model)
                    controls
                }
            }
        } else {
            EmptyStateView(symbol: "music.note", text: "Nothing playing")
        }
    }

    private var artwork: some View {
        ArtworkView(image: model.artwork, cornerRadius: 12)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 110, maxHeight: 110)
            .shadow(color: model.tint.opacity(0.35), radius: 10)
            .overlay(alignment: .bottomTrailing) {
                if let icon = model.sourceAppIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 22, height: 22)
                        .offset(x: 5, y: 5)
                }
            }
            .onTapGesture { model.openSourceApp() }
            .help("Open source app")
    }

    private var controls: some View {
        // Gaps flex (up to 18pt) so the row can shrink in a narrow widget instead of overflowing it.
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            MediaButton(symbol: "backward.fill", size: 14) { model.previous() }
            Spacer(minLength: 2).frame(maxWidth: 18)
            MediaButton(symbol: model.isPlaying ? "pause.fill" : "play.fill", size: 20) { model.togglePlayPause() }
            Spacer(minLength: 2).frame(maxWidth: 18)
            MediaButton(symbol: "forward.fill", size: 14) { model.next() }
            Spacer(minLength: 0)
        }
    }
}

private struct MediaButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .frame(width: size + 16, height: size + 12)
                .background(Circle().fill(.white.opacity(hovering ? 0.12 : 0)))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Progress bar with elapsed/remaining time; drag to seek.
private struct ScrubberView: View {
    let model: NowPlayingModel
    @State private var dragValue: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = max(model.duration, 0.01)
            let current = dragValue ?? model.currentElapsed(at: context.date)
            HStack(spacing: 6) {
                Text(format(current)).frame(width: 34, alignment: .trailing)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule()
                            .fill(model.tint.opacity(0.9))
                            .frame(width: geo.size.width * CGFloat(min(current / duration, 1)))
                    }
                    .frame(height: dragValue == nil ? 4 : 6)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let fraction = min(max(value.location.x / geo.size.width, 0), 1)
                                dragValue = fraction * duration
                            }
                            .onEnded { _ in
                                if let dragValue { model.seek(to: dragValue) }
                                dragValue = nil
                            }
                    )
                }
                .frame(height: 12)
                Text("-" + format(max(0, duration - current))).frame(width: 38, alignment: .leading)
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
            .opacity(model.duration > 0 ? 1 : 0)
        }
    }

    private func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
