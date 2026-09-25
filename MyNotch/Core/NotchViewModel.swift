// Open/close state machine inspired by NotchDrop's NotchViewModel (MIT, Copyright (c) 2024 Lakr Aream).

import AppKit
import Observation
import SwiftUI

enum NotchStatus: Equatable {
    case closed, peek, open
}

enum NotchTab: String, CaseIterable, Identifiable {
    case nook, tray, clipboard, screenshots, sound
    var id: String { rawValue }

    var title: String {
        switch self {
        case .nook: "Nook"
        case .tray: "Tray"
        case .clipboard: "Clipboard"
        case .screenshots: "Screenshots"
        case .sound: "Sound"
        }
    }

    var symbol: String {
        switch self {
        case .nook: "square.grid.2x2"
        case .tray: "tray.full"
        case .clipboard: "doc.on.clipboard"
        case .screenshots: "camera.viewfinder"
        case .sound: "hifispeaker.2.fill"
        }
    }
}

/// Small indicator shown on either side of the closed notch.
enum LiveActivity: Equatable {
    case screenshot(Screenshot)
    case pomodoro
    case media
    case tray(Int)
}

@Observable
final class NotchViewModel {
    let settings = SettingsStore.shared
    let nowPlaying = NowPlayingModel.shared
    let pomodoro = PomodoroTimer.shared
    let tray = TrayStore.shared

    private(set) var status: NotchStatus = .closed
    var tab: NotchTab = .nook
    var dropTargeting = false
    var isHidden = false
    /// Keeps the notch open (used while tuning layout in Settings).
    var pinned = false {
        didSet { if pinned { open() } }
    }

    /// Frame of the screen the notch lives on (global AppKit coordinates, origin bottom-left).
    var screenFrame: CGRect = .zero
    var hasPhysicalNotch = false
    var physicalNotchSize: CGSize = .init(width: 185, height: 32)

    let animation: Animation = .interactiveSpring(duration: 0.45, extraBounce: 0.2, blendDuration: 0.12)

    /// Tabs shown in the header; Clipboard and Screenshots hide while turned off in Settings.
    var visibleTabs: [NotchTab] {
        NotchTab.allCases.filter { tab in
            switch tab {
            case .clipboard: settings.clipboard.enabled
            case .screenshots: settings.screenshots.enabled
            case .nook, .tray, .sound: true
            }
        }
    }

    // MARK: Geometry

    /// Size of the notch itself (real, or the fake one on screens without a notch).
    var baseNotchSize: CGSize {
        let width = hasPhysicalNotch ? physicalNotchSize.width : settings.layout.fakeNotchWidth
        return CGSize(width: max(80, width + settings.layout.notchWidthFineTune), height: physicalNotchSize.height)
    }

    var liveActivity: LiveActivity? {
        let la = settings.liveActivities
        if let shot = ScreenshotStore.shared.justCaptured { return .screenshot(shot) }
        if la.pomodoro, pomodoro.isActive { return .pomodoro }
        if la.media, nowPlaying.showsLiveActivity { return .media }
        if la.trayCount, !tray.items.isEmpty { return .tray(tray.items.count) }
        return nil
    }

    /// Artwork / icon size inside the closed notch: a bit shorter than the notch itself.
    var liveActivityIconSize: CGFloat { max(14, baseNotchSize.height - 12) }

    /// Width added on each side of the camera housing while a live activity shows.
    var liveActivitySideWidth: CGFloat {
        guard let liveActivity else { return 0 }
        switch liveActivity {
        case .pomodoro: return 50 // room for "25:00"
        case .media, .tray, .screenshot: return liveActivityIconSize + 12
        }
    }

    var closedSize: CGSize {
        CGSize(width: baseNotchSize.width + liveActivitySideWidth * 2, height: baseNotchSize.height)
    }

    /// Height of the transparent strip the notch panel covers; the open notch (plus its shadow) must fit.
    static let panelHeight: CGFloat = 520

    /// The open size from Layout settings, kept within what this screen and notch can show:
    /// never wider than the screen (e.g. a 13" Air at "Larger Text" is only 1024pt wide), and never
    /// so narrow that the header can't fit on both sides of the camera (wider notches at "More Space").
    var openSize: CGSize {
        let layout = settings.layout
        let wanted: CGSize = switch tab {
        case .nook: CGSize(width: layout.nookWidth + fixedWidgetsWidth, height: layout.nookHeight)
        case .tray, .clipboard, .screenshots, .sound: CGSize(width: layout.trayWidth, height: layout.trayHeight)
        }
        var width = max(wanted.width, minimumOpenWidth)
        if screenFrame.width > 0 {
            // Leave a margin at the screen edges; the shape's top corners flare out by topCornerRadius.
            width = min(width, screenFrame.width - 2 * (Self.screenEdgeMargin + Self.openTopCornerRadius))
        }
        let height = min(max(wanted.height, baseNotchSize.height + 90), Self.panelHeight - 40)
        return CGSize(width: width, height: height)
    }

    private static let screenEdgeMargin: CGFloat = 16
    private static let openTopCornerRadius: CGFloat = 14

    // Header metrics, shared with OpenNotchView so its layout and this minimum always agree.
    static let headerButtonSize = CGSize(width: 26, height: 22)
    static let headerSpacing: CGFloat = 6
    /// Clear space kept around the camera housing in the header.
    static let headerNotchClearance: CGFloat = 8

    /// Width of the open header's left side: every tab button, plus room for the loading spinner.
    var headerLeadingWidth: CGFloat {
        let count = CGFloat(visibleTabs.count)
        return count * Self.headerButtonSize.width + count * Self.headerSpacing + 16
    }

    /// Width of the right side: the Pomodoro countdown and the settings button.
    var headerTrailingWidth: CGFloat { 44 + Self.headerSpacing + Self.headerButtonSize.width }

    /// Gap in the header that sits under the camera housing.
    var headerNotchGap: CGFloat { baseNotchSize.width + 2 * Self.headerNotchClearance }

    /// Smallest open width that fits the header symmetrically around the notch.
    var minimumOpenWidth: CGFloat {
        let side = max(headerLeadingWidth, headerTrailingWidth)
        return 2 * (side + settings.layout.contentPadding) + headerNotchGap
    }

    /// Widgets with a fixed width (Mirror is a square the row's height) don't share the Nook's
    /// width with the others; nil means "shares by weight".
    func fixedWidth(of kind: WidgetKind, rowHeight: CGFloat) -> CGFloat? {
        switch kind {
        case .mirror: rowHeight
        case .media, .calendar, .shortcuts, .pomodoro: nil
        }
    }

    /// The Nook grows by each enabled fixed-width widget, so turning one on never squeezes the rest.
    private var fixedWidgetsWidth: CGFloat {
        let layout = settings.layout
        let rowHeight = max(0, layout.nookHeight - baseNotchSize.height - layout.contentPadding * 1.5)
        let perWidgetGap = layout.showDividers ? layout.widgetSpacing * 2 + 1 : layout.widgetSpacing
        return settings.widgets.enabled
            .compactMap { fixedWidth(of: $0, rowHeight: rowHeight) }
            .reduce(0) { $0 + $1 + perWidgetGap }
    }

    /// The size the notch is currently drawn at.
    var currentSize: CGSize {
        switch status {
        case .closed: return closedSize
        case .peek: return CGSize(width: closedSize.width + 14, height: closedSize.height + 6)
        case .open: return openSize
        }
    }

    var topCornerRadius: CGFloat { status == .open ? Self.openTopCornerRadius : 6 }
    var bottomCornerRadius: CGFloat {
        status == .open ? settings.layout.cornerRadius : (status == .peek ? 12 : 10)
    }

    /// Rect (global coordinates) of a size centered at the top of the screen.
    func topCenteredRect(_ size: CGSize) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Area that triggers hover/click-to-open while closed.
    var hotRect: CGRect {
        topCenteredRect(closedSize).insetBy(dx: -6, dy: -4)
    }

    var openRect: CGRect { topCenteredRect(openSize) }

    // MARK: Transitions

    func open(tab newTab: NotchTab? = nil) {
        guard !isHidden else { return }
        if let newTab { tab = newTab }
        guard status != .open else { return }
        status = .open
        Haptics.tap()
    }

    func peek() {
        guard status == .closed, !isHidden else { return }
        status = .peek
        Haptics.tap()
    }

    func close() {
        guard status != .closed, !pinned else { return }
        status = .closed
    }

    // MARK: Mouse handling (called by NotchWindowManager's event monitors)

    private var pendingOpen: DispatchWorkItem?
    private var pendingClose: DispatchWorkItem?

    func mouseMoved(to point: NSPoint) {
        let general = settings.general
        switch status {
        case .closed, .peek:
            if hotRect.contains(point) {
                if general.openMode == .hover {
                    scheduleOpen(after: general.hoverDelay)
                } else {
                    peek()
                }
            } else {
                cancelPendingOpen()
                if status == .peek { close() }
            }
        case .open:
            let stillInside = openRect.insetBy(dx: -10, dy: -10).contains(point)
            if stillInside || dropTargeting {
                cancelPendingClose()
            } else if general.openMode == .hover, NSEvent.pressedMouseButtons == 0 {
                scheduleClose(after: general.closeDelay)
            }
        }
    }

    func mouseDown(at point: NSPoint) {
        switch status {
        case .closed, .peek:
            if hotRect.contains(point) {
                cancelPendingOpen()
                open()
            }
        case .open:
            if !openRect.contains(point) { close() }
        }
    }

    private func scheduleOpen(after delay: Double) {
        guard pendingOpen == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            pendingOpen = nil
            if hotRect.contains(NSEvent.mouseLocation) { open() }
        }
        pendingOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingOpen() {
        pendingOpen?.cancel()
        pendingOpen = nil
    }

    private func scheduleClose(after delay: Double) {
        guard pendingClose == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            pendingClose = nil
            if !openRect.insetBy(dx: -10, dy: -10).contains(NSEvent.mouseLocation), !dropTargeting {
                close()
            }
        }
        pendingClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingClose() {
        pendingClose?.cancel()
        pendingClose = nil
    }
}
