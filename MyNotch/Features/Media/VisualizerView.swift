import AppKit
import SwiftUI

/// Animated bars that "dance" while music plays. Not driven by real audio (no permissions needed).
///
/// Each bar is a `CALayer` with a repeating keyframe animation, so the window server animates
/// them on its own: MyNotch does no per-frame work while music plays. (A SwiftUI `TimelineView`
/// re-rendered the view at the display's refresh rate the whole time, about 20% CPU.)
struct VisualizerView: NSViewRepresentable {
    let isPlaying: Bool
    var tint: Color = .white
    var barCount: Int = 5

    func makeNSView(context _: Context) -> VisualizerBarsView {
        VisualizerBarsView(barCount: barCount)
    }

    func updateNSView(_ view: VisualizerBarsView, context _: Context) {
        view.update(color: NSColor(tint).cgColor, playing: isPlaying)
    }
}

final class VisualizerBarsView: NSView {
    private static let idleLevel: CGFloat = 0.18
    private let bars: [CALayer]
    private var playing = false
    private var laidOutSize: CGSize = .zero

    init(barCount: Int) {
        bars = (0 ..< barCount).map { _ in CALayer() }
        super.init(frame: .zero)
        wantsLayer = true
        bars.forEach { layer?.addSublayer($0) }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(color: CGColor, playing: Bool) {
        withoutImplicitAnimations { bars.forEach { $0.backgroundColor = color } }
        guard playing != self.playing else { return }
        self.playing = playing
        restartAnimations()
    }

    override func layout() {
        super.layout()
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size

        let count = CGFloat(bars.count)
        let spacing = max(1.5, bounds.width / (count * 4))
        let width = max(1.5, (bounds.width - spacing * (count - 1)) / count)
        withoutImplicitAnimations {
            for (index, bar) in bars.enumerated() {
                bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height * Self.idleLevel)
                bar.position = CGPoint(x: CGFloat(index) * (width + spacing) + width / 2, y: bounds.midY)
                bar.cornerRadius = width / 2
            }
        }
        restartAnimations() // keyframe heights depend on the view's height
    }

    /// While playing, each bar loops through random heights at its own pace; otherwise it rests low.
    private func restartAnimations() {
        for bar in bars {
            bar.removeAnimation(forKey: "dance")
            guard playing, bounds.height > 0 else { continue }
            let levels = (0 ..< 8).map { _ in CGFloat.random(in: 0.25 ... 1) }
            let animation = CAKeyframeAnimation(keyPath: "bounds.size.height")
            animation.values = (levels + [levels[0]]).map { $0 * bounds.height }
            animation.calculationMode = .cubic
            animation.duration = .random(in: 1.4 ... 2.0)
            animation.timeOffset = .random(in: 0 ... animation.duration)
            animation.repeatCount = .infinity
            bar.add(animation, forKey: "dance")
        }
    }

    private func withoutImplicitAnimations(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
