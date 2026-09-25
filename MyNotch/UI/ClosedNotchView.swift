import SwiftUI

/// Collapsed notch: the black pill, plus "live activity" indicators on either side of the camera.
struct ClosedNotchView: View {
    let vm: NotchViewModel

    var body: some View {
        let side = vm.liveActivitySideWidth
        // Side widths are fully accounted for in vm.closedSize, so nothing overflows or gets clipped.
        HStack(spacing: 0) {
            leading.frame(width: side)
            Spacer(minLength: vm.baseNotchSize.width)
            trailing.frame(width: side)
        }
        .frame(height: vm.closedSize.height)
        .clipped()
    }

    @ViewBuilder private var leading: some View {
        switch vm.liveActivity {
        case let .screenshot(shot):
            Color.clear
                .overlay {
                    Image(nsImage: Thumbnailer.shared.image(forFileAt: shot.url, size: 64))
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(width: iconSize, height: iconSize)
        case .pomodoro:
            PomodoroRing(progress: vm.pomodoro.progress, color: vm.pomodoro.phase.color, lineWidth: 2.5)
                .overlay(
                    Image(systemName: vm.pomodoro.phase.symbol)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(vm.pomodoro.phase.color)
                )
                .frame(width: iconSize, height: iconSize)
        case .media:
            ArtworkView(image: vm.nowPlaying.artwork, cornerRadius: 5)
                .frame(width: iconSize, height: iconSize)
        case .tray:
            Image(systemName: "tray.full.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch vm.liveActivity {
        case .screenshot:
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
        case .pomodoro:
            Text(vm.pomodoro.remainingText)
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(vm.pomodoro.isRunning ? vm.pomodoro.phase.color : .white.opacity(0.6))
        case .media:
            VisualizerView(isPlaying: vm.nowPlaying.isPlaying, tint: vm.nowPlaying.tint, barCount: 4)
                .frame(width: iconSize, height: iconSize * 0.7)
        case let .tray(count):
            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        case nil:
            EmptyView()
        }
    }

    private var iconSize: CGFloat { vm.liveActivityIconSize }
}
