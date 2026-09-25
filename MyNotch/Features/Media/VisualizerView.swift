import SwiftUI

/// Animated bars that "dance" while music plays. Not driven by real audio (no permissions needed).
struct VisualizerView: View {
    let isPlaying: Bool
    var tint: Color = .white
    var barCount: Int = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: !isPlaying)) { context in
            GeometryReader { geo in
                let spacing = max(1.5, geo.size.width / CGFloat(barCount * 4))
                let barWidth = (geo.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(0 ..< barCount, id: \.self) { index in
                        Capsule()
                            .fill(tint)
                            .frame(
                                width: max(1.5, barWidth),
                                height: geo.size.height * level(index, context.date)
                            )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(.easeInOut(duration: 0.18), value: context.date)
            }
        }
    }

    /// Smooth pseudo-random level per bar from a few summed sines.
    private func level(_ index: Int, _ date: Date) -> CGFloat {
        guard isPlaying else { return 0.18 }
        let t = date.timeIntervalSinceReferenceDate
        let i = Double(index)
        let value = sin(t * (5.1 + i * 1.3) + i * 1.7) * 0.5
            + sin(t * (8.3 - i * 0.9) + i * 0.6) * 0.3
            + sin(t * 2.2 + i) * 0.2
        return CGFloat(0.25 + 0.75 * abs(value))
    }
}
