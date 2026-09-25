import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, layout, widgets, pomodoro, tray, clipboard, screenshots, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .layout: "Layout"
        case .widgets: "Widgets"
        case .pomodoro: "Pomodoro"
        case .tray: "Tray"
        case .clipboard: "Clipboard"
        case .screenshots: "Screenshots"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .layout: "rectangle.3.group"
        case .widgets: "square.grid.2x2"
        case .pomodoro: "timer"
        case .tray: "tray.full"
        case .clipboard: "doc.on.clipboard"
        case .screenshots: "camera.viewfinder"
        case .about: "info.circle"
        }
    }
}

@Observable
final class SettingsNavigation {
    var pane: SettingsPane = .general
}

/// Hosts the settings UI in a normal window (the app has no Dock icon, so this activates it explicitly).
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let navigation = SettingsNavigation()

    func show(pane: SettingsPane? = nil) {
        if let pane { navigation.pane = pane }
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "MyNotch Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(navigation: navigation))
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_: Notification) {
        NotchWindowManager.shared.viewModel.pinned = false
        NotchWindowManager.shared.viewModel.close()
    }
}
