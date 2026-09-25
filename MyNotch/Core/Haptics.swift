import AppKit

enum Haptics {
    private static var last = Date.distantPast

    /// Light trackpad tick, throttled so repeated hovers don't buzz constantly.
    static func tap() {
        guard SettingsStore.shared.general.haptics, Date().timeIntervalSince(last) > 0.4 else { return }
        last = Date()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
