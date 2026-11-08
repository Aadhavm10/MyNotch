import AppKit
import Observation
import SwiftUI

/// What the donut shows: the formats on offer and the slice under the cursor.
@Observable
final class DonutModel {
    var formats: [ConvertFormat] = []
    var hovered: ConvertFormat?
    /// Drives the pop-in animation each time the donut opens.
    var visible = false
}

/// Transparent, non-activating panel above everything (including the notch) that hosts the donut.
final class DonutPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .popUpMenu
        collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle, .transient]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Opens the format donut at the cursor while files are Option-dragged (see `NotchWindowManager`).
final class DonutController {
    static let shared = DonutController()

    static let diameter: CGFloat = 280
    /// Slices beyond this get too thin to hit mid-drag.
    static let maxSlices = 8

    let model = DonutModel()
    private var panel: DonutPanel?

    var isShown: Bool { panel?.isVisible == true }

    func show(at point: NSPoint, formats: [ConvertFormat]) {
        model.formats = Array(formats.prefix(Self.maxSlices))
        model.hovered = nil
        model.visible = false

        let panel = panel ?? makePanel()
        let size = Self.diameter
        var frame = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        // Keep the whole donut on the screen the cursor is on.
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            let bounds = screen.frame
            frame.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - size)
            frame.origin.y = min(max(frame.minY, bounds.minY), bounds.maxY - size)
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        DispatchQueue.main.async {
            withAnimation(.spring(duration: 0.25, bounce: 0.3)) { self.model.visible = true }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        model.hovered = nil
        model.visible = false
    }

    private func makePanel() -> DonutPanel {
        let panel = DonutPanel()
        let hosting = NotchHostingView(rootView: DonutView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        return panel
    }
}
