import SwiftUI

struct PomodoroRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)
        }
    }
}

struct PomodoroWidget: View {
    let timer: PomodoroTimer

    var body: some View {
        // Ring beside the controls when there's room; stacked and smaller in a narrow Nook.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                ring(size: 92, timeSize: 17)
                VStack(alignment: .leading, spacing: 8) {
                    controls
                    goalDots
                    historyBars
                }
            }
            VStack(spacing: 6) {
                ring(size: 64, timeSize: 13)
                controls
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ring(size: CGFloat, timeSize: CGFloat) -> some View {
        ZStack {
            PomodoroRing(progress: timer.progress, color: timer.phase.color, lineWidth: size > 70 ? 5 : 4)
            VStack(spacing: 0) {
                Text(timer.remainingText)
                    .font(.system(size: timeSize, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text(timer.phase.title)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(timer.phase.color)
                    .textCase(.uppercase)
            }
        }
        .frame(width: size, height: size)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            CircleButton(symbol: timer.isRunning ? "pause.fill" : "play.fill", prominent: true) { timer.toggle() }
            CircleButton(symbol: "forward.end.fill") { timer.skip() }
                .disabled(!timer.isActive)
            CircleButton(symbol: "arrow.counterclockwise") { timer.reset() }
                .disabled(!timer.isActive)
        }
    }

    /// A dot per session of today's goal, then "done/goal"; just the count when there's no room for dots.
    private var goalDots: some View {
        let goal = max(1, SettingsStore.shared.pomodoro.dailyGoal)
        let done = timer.stats.todayCount
        let count = Text("\(done)/\(goal)")
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
            .fixedSize()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 3) {
                ForEach(0 ..< min(goal, 12), id: \.self) { index in
                    Circle()
                        .fill(index < done ? PomodoroPhase.work.color : .white.opacity(0.15))
                        .frame(width: 6, height: 6)
                }
                count
            }
            count
        }
        .help("Focus sessions today")
    }

    private var historyBars: some View {
        let history = timer.stats.history(days: 7)
        let maxCount = max(1, history.map(\.count).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(history, id: \.date) { entry in
                VStack(spacing: 2) {
                    Capsule()
                        .fill(Calendar.current.isDateInToday(entry.date) ? PomodoroPhase.work.color : .white.opacity(0.35))
                        .frame(width: 6, height: max(2, 18 * CGFloat(entry.count) / CGFloat(maxCount)))
                    Text(entry.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .help("\(entry.count) on \(entry.date.formatted(date: .abbreviated, time: .omitted))")
            }
        }
        .frame(height: 30, alignment: .bottom)
    }
}

private struct CircleButton: View {
    let symbol: String
    var prominent = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
                .foregroundStyle(prominent ? .black : .white)
                .background(Circle().fill(prominent ? Color.white.opacity(hovering ? 1 : 0.9) : .white.opacity(hovering ? 0.2 : 0.1)))
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
