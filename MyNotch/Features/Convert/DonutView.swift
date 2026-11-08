import SwiftUI

/// Radial format picker: drop the dragged files on a slice to convert them; the hole in the
/// middle cancels.
struct DonutView: View {
    let model: DonutModel

    static let outerInset: CGFloat = 10
    static let innerRadius: CGFloat = 50

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let outer = min(geo.size.width, geo.size.height) / 2 - Self.outerInset
            let count = model.formats.count
            ZStack {
                Circle()
                    .fill(.black.opacity(0.94))
                    .frame(width: outer * 2, height: outer * 2)
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
                ForEach(Array(model.formats.enumerated()), id: \.element) { index, format in
                    slice(format, index: index, count: count, center: center, outer: outer)
                }
                centerLabel
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Circle().inset(by: Self.outerInset))
            .onDrop(of: [.fileURL, .data], delegate: DonutDropDelegate(
                model: model, center: center, inner: Self.innerRadius, outer: outer
            ))
        }
        .scaleEffect(model.visible ? 1 : 0.6)
        .opacity(model.visible ? 1 : 0)
        .environment(\.colorScheme, .dark)
    }

    private func slice(_ format: ConvertFormat, index: Int, count: Int, center: CGPoint, outer: CGFloat) -> some View {
        let hovered = model.hovered == format
        let span = 360 / Double(count)
        let mid = Self.angle(of: index, count: count)
        let labelRadius = (Self.innerRadius + outer) / 2
        let gap = count > 1 ? 1.5 : 0
        return ZStack {
            DonutSlice(
                startAngle: .degrees(mid - span / 2 + gap),
                endAngle: .degrees(mid + span / 2 - gap),
                innerRadius: Self.innerRadius + 3,
                outerRadius: outer - 3
            )
            .fill(.white.opacity(hovered ? 0.95 : 0.14))
            VStack(spacing: 3) {
                Image(systemName: format.symbol).font(.system(size: 13, weight: .semibold))
                Text(format.title).font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(hovered ? .black : .white.opacity(0.9))
            .position(
                x: center.x + cos(mid * .pi / 180) * labelRadius,
                y: center.y + sin(mid * .pi / 180) * labelRadius
            )
        }
        .animation(.easeOut(duration: 0.1), value: hovered)
    }

    private var centerLabel: some View {
        VStack(spacing: 2) {
            Image(systemName: model.hovered == nil ? "xmark" : "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .semibold))
            Text(model.hovered.map { "To \($0.title)" } ?? "Cancel")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white.opacity(0.7))
        .frame(width: Self.innerRadius * 1.6)
    }

    /// Middle of slice `index` in degrees, clockwise from the top (SwiftUI's y axis points down).
    static func angle(of index: Int, count: Int) -> Double {
        -90 + Double(index) * 360 / Double(count)
    }

    /// Slice under `point`, or nil in the hole or outside the ring.
    static func slice(at point: CGPoint, center: CGPoint, inner: CGFloat, outer: CGFloat, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let dx = point.x - center.x, dy = point.y - center.y
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > inner, distance < outer + 20 else { return nil }
        let span = 360 / Double(count)
        var degrees = atan2(dy, dx) * 180 / .pi + 90 + span / 2
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }
        return min(count - 1, Int(degrees / span))
    }
}

private struct DonutDropDelegate: DropDelegate {
    let model: DonutModel
    let center: CGPoint
    let inner: CGFloat
    let outer: CGFloat

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let index = DonutView.slice(at: info.location, center: center, inner: inner, outer: outer, count: model.formats.count)
        let hovered = index.map { model.formats[$0] }
        if hovered != model.hovered {
            model.hovered = hovered
            if hovered != nil { Haptics.tap() }
        }
        return DropProposal(operation: hovered == nil ? .forbidden : .copy)
    }

    func dropExited(info _: DropInfo) {
        model.hovered = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let format = model.hovered else { return false }
        ConvertService.shared.convert(info.itemProviders(for: [.fileURL, .data]), to: format)
        DonutController.shared.hide()
        return true
    }
}

/// A ring segment between two angles.
struct DonutSlice: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}
