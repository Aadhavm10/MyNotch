import SwiftUI

@main
struct MyNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("MyNotch", systemImage: "rectangle.topthird.inset.filled") {
            MenuBarContent()
        }
    }
}

private struct MenuBarContent: View {
    private let manager = NotchWindowManager.shared
    private let pomodoro = PomodoroTimer.shared

    var body: some View {
        Button("Open Notch") { manager.viewModel.open(tab: .nook) }
            .disabled(manager.viewModel.isHidden)
        Button("Open Tray") { manager.viewModel.open(tab: .tray) }
            .disabled(manager.viewModel.isHidden)
        Button(manager.viewModel.isHidden ? "Show Notch" : "Hide Notch") {
            manager.setHidden(!manager.viewModel.isHidden)
        }
        Divider()
        Text("Pomodoro · \(pomodoro.phase.title) \(pomodoro.remainingText)")
        Button(pomodoro.isRunning ? "Pause Pomodoro" : (pomodoro.isActive ? "Resume Pomodoro" : "Start Pomodoro")) {
            pomodoro.toggle()
        }
        if pomodoro.isActive {
            Button("Skip Phase") { pomodoro.skip() }
            Button("Reset Pomodoro") { pomodoro.reset() }
        }
        Divider()
        Button("Settings…") { SettingsWindowController.shared.show() }
            .keyboardShortcut(",")
        Button("Quit MyNotch") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
