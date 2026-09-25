import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        terminateOtherInstances()
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self

        // Every launch, so a moved or reinstalled copy re-registers itself as the login item.
        SettingsStore.shared.applyLaunchAtLogin()

        NotchWindowManager.shared.start()
        NowPlayingModel.shared.start()
        _ = TrayStore.shared
        _ = ClipboardStore.shared
        _ = ScreenshotStore.shared
    }

    func applicationWillTerminate(_: Notification) {
        NowPlayingModel.shared.stop()
        CameraService.shared.stop()
    }

    /// Re-launching the app (e.g. from Finder) opens the notch instead of doing nothing.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        NotchWindowManager.shared.viewModel.open()
        return true
    }

    /// URL scheme for automation (Shortcuts, Raycast, scripts):
    /// mynotch://open[?tab=nook|tray], mynotch://close, mynotch://pomodoro/{toggle,skip,reset}, mynotch://settings
    func application(_: NSApplication, open urls: [URL]) {
        let vm = NotchWindowManager.shared.viewModel
        for url in urls where url.scheme == "mynotch" {
            let tab = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "tab" }?.value.flatMap(NotchTab.init(rawValue:))
            switch (url.host ?? "", url.path) {
            case ("open", _): vm.open(tab: tab)
            case ("close", _): vm.close()
            case ("settings", _): SettingsWindowController.shared.show()
            case ("pomodoro", "/toggle"): PomodoroTimer.shared.toggle()
            case ("pomodoro", "/skip"): PomodoroTimer.shared.skip()
            case ("pomodoro", "/reset"): PomodoroTimer.shared.reset()
            #if DEBUG
            case ("debug", "/snapshot"): NotchWindowManager.shared.debugSnapshot()
            case ("debug", "/simulate"):
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                func number(_ name: String) -> CGFloat? {
                    items.first { $0.name == name }?.value.flatMap(Double.init).map { CGFloat($0) }
                }
                let notch = number("notchWidth").map { CGSize(width: $0, height: number("notchHeight") ?? 32) }
                NotchWindowManager.shared.debugSimulate(screenWidth: number("screenWidth"), notchSize: notch)
            case ("debug", "/pin"):
                // Holds the notch open for screenshots even while the mouse is elsewhere.
                let on = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "on" }?.value == "1"
                vm.pinned = on
                if !on { vm.close() }
            #endif
            default: NSSound.beep()
            }
        }
    }

    /// Only one notch at a time: a newly launched copy replaces any older one.
    private func terminateOtherInstances() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let me = NSRunningApplication.current.processIdentifier
        NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != me }
            .forEach { $0.terminate() }
    }

    // Show Pomodoro banners even while MyNotch is frontmost.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
