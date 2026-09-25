import EventKit
import SwiftUI

struct CalendarWidget: View {
    private let service = CalendarService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Date(), format: .dateTime.weekday(.abbreviated))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
                Text(Date(), format: .dateTime.day())
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
            }
            content
        }
        .onAppear { service.refresh() }
    }

    @ViewBuilder private var content: some View {
        if service.status == .notDetermined {
            Button("Allow Calendar Access") { service.requestAccess() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !service.hasAccess {
            Button {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            } label: {
                EmptyStateView(symbol: "calendar.badge.exclamationmark", text: "Calendar access denied — open Settings")
            }
            .buttonStyle(.plain)
        } else if service.events.isEmpty {
            EmptyStateView(symbol: "calendar", text: "No upcoming events")
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(service.events, id: \.calendarItemIdentifierWithDate) { event in
                        EventRow(event: event)
                            .onTapGesture { service.openCalendarApp(at: event.startDate) }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

private struct EventRow: View {
    let event: EKEvent

    var body: some View {
        let isNow = event.startDate <= Date() && event.endDate > Date()
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "Untitled")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(timeText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isNow ? Color(cgColor: event.calendar.cgColor) : .white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
    }

    private var timeText: String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(event.startDate) {
            day = ""
        } else if calendar.isDateInTomorrow(event.startDate) {
            day = "Tomorrow "
        } else {
            day = event.startDate.formatted(.dateTime.weekday(.abbreviated)) + " "
        }
        if event.isAllDay { return day + "All day" }
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(day)\(start) – \(end)"
    }
}

private extension EKEvent {
    var calendarItemIdentifierWithDate: String {
        "\(calendarItemIdentifier)-\(startDate.timeIntervalSince1970)"
    }
}
