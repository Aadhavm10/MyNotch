import AppKit
import Observation
import SwiftUI
import UserNotifications

enum PomodoroPhase: String, Codable {
    case work, shortBreak, longBreak

    var title: String {
        switch self {
        case .work: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    var symbol: String { self == .work ? "brain.head.profile" : "cup.and.saucer.fill" }
    var color: Color { self == .work ? Color(red: 1, green: 0.42, blue: 0.36) : Color(red: 0.36, green: 0.85, blue: 0.55) }
}

/// Work/break cycle timer. Uses an end date rather than counting ticks, so it stays correct across sleep.
@Observable
final class PomodoroTimer {
    static let shared = PomodoroTimer()

    enum State: Equatable {
        case idle
        case running(end: Date)
        case paused(remaining: TimeInterval)
    }

    private(set) var phase: PomodoroPhase = .work
    private(set) var state: State = .idle
    private(set) var remaining: TimeInterval = 0
    /// Focus sessions completed since the last long break.
    private(set) var roundInCycle = 0
    let stats = PomodoroStats()

    @ObservationIgnored private var ticker: Timer?
    private var settings: PomodoroSettings { SettingsStore.shared.pomodoro }

    private init() {
        remaining = duration(of: .work)
    }

    // MARK: Derived

    var isActive: Bool { state != .idle }
    var isRunning: Bool { if case .running = state { return true } else { return false } }

    var progress: Double {
        let total = duration(of: phase)
        guard total > 0 else { return 0 }
        return min(max(1 - remaining / total, 0), 1)
    }

    var remainingText: String {
        let s = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    func duration(of phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .work: settings.workMinutes * 60
        case .shortBreak: settings.shortBreakMinutes * 60
        case .longBreak: settings.longBreakMinutes * 60
        }
    }

    // MARK: Controls

    func toggle() {
        switch state {
        case .idle: start()
        case .running: pause()
        case .paused: resume()
        }
    }

    func start(phase newPhase: PomodoroPhase? = nil) {
        if let newPhase { phase = newPhase }
        requestNotificationPermission()
        run(for: duration(of: phase))
    }

    func pause() {
        guard case let .running(end) = state else { return }
        ticker?.invalidate()
        remaining = max(0, end.timeIntervalSinceNow)
        state = .paused(remaining: remaining)
    }

    func resume() {
        guard case let .paused(left) = state else { return }
        run(for: left)
    }

    /// Stops the timer and goes back to a fresh focus session.
    func reset() {
        ticker?.invalidate()
        state = .idle
        phase = .work
        roundInCycle = 0
        remaining = duration(of: .work)
    }

    /// Ends the current phase early without counting it.
    func skip() {
        advance(completed: false)
    }

    /// Settings changed while idle: show the new focus length.
    func settingsChanged() {
        if state == .idle { remaining = duration(of: phase) }
    }

    // MARK: Private

    private func run(for seconds: TimeInterval) {
        ticker?.invalidate()
        let end = Date().addingTimeInterval(seconds)
        state = .running(end: end)
        remaining = seconds
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard case let .running(end) = state else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 { advance(completed: true) }
    }

    private func advance(completed: Bool) {
        ticker?.invalidate()
        let finished = phase
        if finished == .work {
            if completed { stats.recordCompletion() }
            roundInCycle += 1
        }
        let next: PomodoroPhase
        if finished == .work {
            next = roundInCycle >= max(1, settings.roundsBeforeLongBreak) ? .longBreak : .shortBreak
        } else {
            if finished == .longBreak { roundInCycle = 0 }
            next = .work
        }
        phase = next
        if completed { announce(finished: finished, next: next) }

        let autoStart = next == .work ? settings.autoStartWork : settings.autoStartBreaks
        if autoStart {
            run(for: duration(of: next))
        } else {
            remaining = duration(of: next)
            state = .paused(remaining: remaining)
        }
    }

    private func announce(finished: PomodoroPhase, next: PomodoroPhase) {
        if settings.playSound {
            NSSound(named: NSSound.Name(settings.soundName))?.play()
        }
        if settings.notify {
            let content = UNMutableNotificationContent()
            content.title = finished == .work ? "Focus session done 🍅" : "Break's over"
            content.body = finished == .work
                ? "Time for a \(next == .longBreak ? "long" : "short") break. \(stats.todayCount) today."
                : "Ready for another focus session?"
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
        Haptics.tap()
    }

    private func requestNotificationPermission() {
        guard settings.notify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

/// Completed focus sessions per day, stored in UserDefaults as {"yyyy-MM-dd": count}.
@Observable
final class PomodoroStats {
    private(set) var counts: [String: Int]
    private static let key = "pomodoro.dailyCounts"

    init() {
        counts = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
    }

    var todayCount: Int { counts[Self.dayKey(Date())] ?? 0 }

    /// Last `days` days, oldest first.
    func history(days: Int = 7) -> [(date: Date, count: Int)] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0 ..< days).reversed().compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (date, counts[Self.dayKey(date)] ?? 0)
        }
    }

    func recordCompletion() {
        counts[Self.dayKey(Date()), default: 0] += 1
        UserDefaults.standard.set(counts, forKey: Self.key)
    }

    func resetAll() {
        counts = [:]
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
