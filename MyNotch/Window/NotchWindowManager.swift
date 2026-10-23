// Screen selection and rebuild logic adapted from NotchDrop's AppDelegate/NotchWindowController
// (https://github.com/Lakr233/NotchDrop), MIT License, Copyright (c) 2024 Lakr Aream.

import AppKit
import SwiftUI

/// Owns the notch panel, keeps it on the right screen, and feeds mouse events to the view model.
final class NotchWindowManager {
    static let shared = NotchWindowManager()

    let viewModel = NotchViewModel()
    private var panel: NotchPanel?
    private var monitors: [EventMonitor] = []
    private var observers: [NSObjectProtocol] = []
    private var screenTimer: Timer?

    private let panelHeight = NotchViewModel.panelHeight

    var contentView: NSView? { panel?.contentView }

    func start() {
        let panel = NotchPanel(contentRect: .zero)
        let hosting = NotchHostingView(rootView: NotchRootView(vm: viewModel))
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel

        startMonitors()
        observeScreens()
        relocate(force: true)
        panel.orderFrontRegardless()
    }

    func setHidden(_ hidden: Bool) {
        viewModel.close()
        viewModel.isHidden = hidden
        if hidden { panel?.orderOut(nil) } else { panel?.orderFrontRegardless() }
    }

    // MARK: Screens

    /// The screen that should show the notch: the active screen, falling back to the built-in notch.
    private func targetScreen() -> NSScreen? {
        let active = NSScreen.main
        if let active, active.hasNotch { return active }
        if SettingsStore.shared.general.showOnNonNotchScreens, let active { return active }
        if let builtIn = NSScreen.builtIn, builtIn.hasNotch { return builtIn }
        return nil
    }

    private var currentScreenID: CGDirectDisplayID?
    private var currentScreenFrame: CGRect = .zero

    private func relocate(force: Bool = false) {
        guard let panel else { return }
        // Never jump screens while the user is interacting with the notch.
        guard force || viewModel.status == .closed else { return }
        guard let screen = targetScreen() else {
            panel.orderOut(nil)
            return
        }
        if !force, screen.displayID == currentScreenID, screen.frame == currentScreenFrame { return }
        currentScreenID = screen.displayID
        currentScreenFrame = screen.frame

        viewModel.screenFrame = screen.frame
        viewModel.hasPhysicalNotch = screen.hasNotch
        viewModel.physicalNotchSize = screen.hasNotch
            ? screen.notchSize
            : CGSize(width: 185, height: screen.menuBarHeight)
        #if DEBUG
        applyDebugSimulation(on: screen)
        #endif

        let frame = CGRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - panelHeight,
            width: screen.frame.width,
            height: panelHeight
        )
        panel.setFrame(frame, display: true)
        if !viewModel.isHidden { panel.orderFrontRegardless() }
    }

    private func observeScreens() {
        let nc = NotificationCenter.default
        let wnc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.relocate(force: true) })
        observers.append(wnc.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.relocate() })
        observers.append(wnc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.relocate() })
        observers.append(wnc.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.relocate(force: true) })

        // Cheap safety net for focus changes between displays that post no notification.
        screenTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.relocate()
        }
    }

    // MARK: Mouse

    /// Drag pasteboard change count at the last mouse down; a drag session writes to the
    /// pasteboard, so a change while the button is held means something is being dragged.
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount

    private func startMonitors() {
        let move = EventMonitor(mask: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            guard let self else { return }
            if event.type == .leftMouseDragged {
                if !viewModel.isDragging, NSPasteboard(name: .drag).changeCount != dragChangeCount {
                    viewModel.isDragging = true
                }
            } else if viewModel.isDragging {
                viewModel.isDragging = false // buttons are up, so any drag has ended
            }
            viewModel.mouseMoved(to: NSEvent.mouseLocation)
        }
        let down = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            dragChangeCount = NSPasteboard(name: .drag).changeCount
            viewModel.mouseDown(at: NSEvent.mouseLocation)
        }
        let up = EventMonitor(mask: [.leftMouseUp]) { [weak self] _ in
            self?.viewModel.isDragging = false
        }
        monitors = [move, down, up]
        monitors.forEach { $0.start() }
    }

    #if DEBUG
    /// Lays the notch out as if on another MacBook (dev only), centered on the real screen:
    /// mynotch://debug/simulate?screenWidth=1024&notchWidth=160&notchHeight=38 — no parameters resets.
    private var debugScreenWidth: CGFloat?
    private var debugNotchSize: CGSize?

    func debugSimulate(screenWidth: CGFloat?, notchSize: CGSize?) {
        debugScreenWidth = screenWidth
        debugNotchSize = notchSize
        relocate(force: true)
    }

    private func applyDebugSimulation(on screen: NSScreen) {
        if let width = debugScreenWidth {
            viewModel.screenFrame = CGRect(
                x: screen.frame.midX - width / 2, y: screen.frame.minY, width: width, height: screen.frame.height
            )
        }
        if let notch = debugNotchSize {
            viewModel.hasPhysicalNotch = true
            viewModel.physicalNotchSize = notch
        }
    }

    /// Renders the notch view to ~/Library/Application Support/MyNotch/debug-snapshot.png (dev only).
    @MainActor func debugSnapshot() {
        let size = CGSize(width: min(viewModel.screenFrame.width, 1100), height: 420)
        let renderer = ImageRenderer(
            content: NotchRootView(vm: viewModel)
                .frame(width: size.width, height: size.height)
                .background(Color(white: 0.85))
        )
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: TrayStore.rootDirectory.appendingPathComponent("debug-snapshot.png"))
    }
    #endif
}
