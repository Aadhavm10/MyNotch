import SwiftUI

/// Row of format chips at the bottom of the Tray while files are dragged over the notch.
/// The chips are drawn here; `NotchDropDelegate` hit-tests their frames to pick the format.
struct ConvertStrip: View {
    let vm: NotchViewModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.trailing, 2)
            ForEach(vm.dragTargets) { format in
                chip(format)
                    .onGeometryChange(for: CGRect.self) {
                        $0.frame(in: .named(NotchRootView.coordinateSpace))
                    } action: { vm.convertChipFrames[format] = $0 }
            }
        }
        .frame(maxWidth: .infinity)
        .onDisappear { vm.convertChipFrames = [:] }
    }

    private func chip(_ format: ConvertFormat) -> some View {
        let hovered = vm.hoveredConvertFormat == format
        return HStack(spacing: 4) {
            Image(systemName: format.symbol).font(.system(size: 10, weight: .semibold))
            Text(format.title).font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .foregroundStyle(hovered ? .black : .white.opacity(0.85))
        .background(Capsule().fill(hovered ? .white : .white.opacity(0.1)))
        .scaleEffect(hovered ? 1.08 : 1)
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
