import AppKit
import EventKit
import Observation

@Observable
final class CalendarService {
    static let shared = CalendarService()

    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var events: [EKEvent] = []
    private(set) var calendars: [EKCalendar] = []

    @ObservationIgnored let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var refreshTimer: Timer?

    var hasAccess: Bool { status == .fullAccess }

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in self?.refresh() }
        // Roll "upcoming" forward as time passes.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
        if hasAccess { refresh() }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.status = EKEventStore.authorizationStatus(for: .event)
                self?.refresh()
            }
        }
    }

    func refresh() {
        status = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else { return }
        calendars = store.calendars(for: .event).sorted { $0.title < $1.title }

        let settings = SettingsStore.shared.widgets
        let selected = calendars.filter { settings.calendarIDs.isEmpty || settings.calendarIDs.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else {
            events = []
            return
        }
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: max(1, settings.calendarDaysAhead), to: start) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
        events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
    }

    func openCalendarApp(at date: Date) {
        // Calendar.app understands ical:// URLs with a timestamp since 2001.
        let url = URL(string: "ical://?date=\(Int(date.timeIntervalSinceReferenceDate))")
        if let url, NSWorkspace.shared.open(url) { return }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
        }
    }
}
