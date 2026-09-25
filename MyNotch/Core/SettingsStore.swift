import Foundation
import Observation
import ServiceManagement

enum OpenMode: String, Codable, CaseIterable, Identifiable {
    case hover, click
    var id: String { rawValue }
    var title: String { self == .hover ? "Hover" : "Click" }
}

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case media, calendar, shortcuts, mirror, pomodoro
    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Media"
        case .calendar: "Calendar"
        case .shortcuts: "Shortcuts"
        case .mirror: "Mirror"
        case .pomodoro: "Pomodoro"
        }
    }

    var symbol: String {
        switch self {
        case .media: "music.note"
        case .calendar: "calendar"
        case .shortcuts: "square.stack.3d.up"
        case .mirror: "camera"
        case .pomodoro: "timer"
        }
    }
}

struct GeneralSettings: Codable, Equatable {
    var openMode: OpenMode = .hover
    var hoverDelay: Double = 0.15
    var closeDelay: Double = 0.2
    var launchAtLogin: Bool = true
    var showOnNonNotchScreens: Bool = true
    var haptics: Bool = true
    var openTrayOnFileDrag: Bool = true
}

struct LayoutSettings: Codable, Equatable {
    var notchWidthFineTune: Double = 0
    var fakeNotchWidth: Double = 185
    var contentPadding: Double = 12
    var widgetSpacing: Double = 12
    var cornerRadius: Double = 24
    var nookWidth: Double = 740
    var nookHeight: Double = 190
    var trayWidth: Double = 600
    var trayHeight: Double = 170
    var showDividers: Bool = true
}

struct WidgetSettings: Codable, Equatable {
    var enabled: [WidgetKind] = [.media, .calendar, .pomodoro] // Mirror is opt-in (Settings → Widgets → Mirror)
    var calendarIDs: [String] = [] // empty = all calendars
    var calendarDaysAhead: Int = 2
    var shortcuts: [String] = []
    var shortcutButtonWidth: Double = 110
    var mirrorAutoStart: Bool = false
    var mirrorDeviceID: String? = nil
}

struct LiveActivitySettings: Codable, Equatable {
    var media: Bool = true
    var pomodoro: Bool = true
    var trayCount: Bool = true
    var screenshots: Bool = true
    var hideMediaAfterPause: Double = 10
}

struct PomodoroSettings: Codable, Equatable {
    var workMinutes: Double = 25
    var shortBreakMinutes: Double = 5
    var longBreakMinutes: Double = 15
    var roundsBeforeLongBreak: Int = 4
    var autoStartBreaks: Bool = true
    var autoStartWork: Bool = false
    var playSound: Bool = true
    var soundName: String = "Glass"
    var notify: Bool = true
    var dailyGoal: Int = 8
}

struct ClipboardSettings: Codable, Equatable {
    var enabled: Bool = true
    var persist: Bool = true
    var maxItems: Int = 50
    /// Copies made while one of these apps is frontmost are never recorded.
    var ignoredBundleIDs: [String] = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.apple.keychainaccess", "com.apple.Passwords", "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal",
    ]
}

struct ScreenshotSettings: Codable, Equatable {
    var enabled: Bool = true
    var maxItems: Int = 20
    var maxAgeDays: Double = 7 // 0 = no limit
}

struct TraySettings: Codable, Equatable {
    var keepDays: Double = 0 // 0 = forever
}

/// All user-configurable settings, persisted as JSON blobs in UserDefaults (one key per group).
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    var general: GeneralSettings { didSet { save(general, "general"); applyLaunchAtLogin() } }
    var layout: LayoutSettings { didSet { save(layout, "layout") } }
    var widgets: WidgetSettings { didSet { save(widgets, "widgets") } }
    var liveActivities: LiveActivitySettings { didSet { save(liveActivities, "liveActivities") } }
    var pomodoro: PomodoroSettings { didSet { save(pomodoro, "pomodoro") } }
    var tray: TraySettings { didSet { save(tray, "tray") } }
    var clipboard: ClipboardSettings { didSet { save(clipboard, "clipboard") } }
    var screenshots: ScreenshotSettings { didSet { save(screenshots, "screenshots") } }

    private init() {
        general = Self.load("general", default: .init())
        layout = Self.load("layout", default: .init())
        widgets = Self.load("widgets", default: .init())
        liveActivities = Self.load("liveActivities", default: .init())
        pomodoro = Self.load("pomodoro", default: .init())
        tray = Self.load("tray", default: .init())
        clipboard = Self.load("clipboard", default: .init())
        screenshots = Self.load("screenshots", default: .init())
    }

    func resetLayout() { layout = .init() }

    /// Only the installed copy (in /Applications or ~/Applications) registers as a login item,
    /// so running a debug build from Xcode's build folder never repoints "open at login" there.
    private var isInstalledCopy: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    private static let loginItemPathKey = "loginItemPath"

    func applyLaunchAtLogin() {
        guard isInstalledCopy else { return }
        let service = SMAppService.mainApp
        let defaults = UserDefaults.standard
        let path = Bundle.main.bundlePath
        do {
            if general.launchAtLogin {
                // An older registration may point at another copy (e.g. a build folder); replace it.
                if service.status == .enabled, defaults.string(forKey: Self.loginItemPathKey) != path {
                    try? service.unregister()
                }
                if service.status != .enabled { try service.register() }
                defaults.set(path, forKey: Self.loginItemPathKey)
            } else if service.status == .enabled {
                try service.unregister()
                defaults.removeObject(forKey: Self.loginItemPathKey)
            }
        } catch {
            NSLog("MyNotch: launch at login update failed: \(error.localizedDescription)")
        }
    }

    /// Saved values layered over the defaults, so adding a new setting later doesn't throw away
    /// the rest of a group that was saved before it existed.
    private static func load<T: Codable>(_ key: String, default value: T) -> T {
        guard let data = UserDefaults.standard.data(forKey: "settings.\(key)"),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaults = (try? JSONEncoder().encode(value))
              .flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        else { return value }
        let merged = defaults.merging(saved) { _, saved in saved }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let decoded = try? JSONDecoder().decode(T.self, from: mergedData)
        else { return value }
        return decoded
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: "settings.\(key)")
    }
}
