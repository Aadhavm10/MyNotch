import SwiftUI

/// Expanded notch: a header row beside the camera with tabs and buttons, then the tab content.
struct OpenNotchView: View {
    @Bindable var vm: NotchViewModel

    var body: some View {
        let padding = vm.settings.layout.contentPadding
        VStack(spacing: 0) {
            header
                .frame(height: vm.baseNotchSize.height)
                .padding(.horizontal, padding)
            Group {
                switch vm.tab {
                case .nook: NookView(vm: vm)
                case .tray: TrayView(vm: vm)
                case .clipboard: ClipboardView(vm: vm)
                case .screenshots: ScreenshotShelfView(vm: vm)
                case .sound: SoundView()
                }
            }
            .padding(.horizontal, padding)
            .padding(.bottom, padding)
            .padding(.top, padding * 0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: vm.openSize.width, height: vm.openSize.height, alignment: .top)
    }

    /// Tabs on the left, settings on the right, and a gap exactly under the camera housing.
    /// Both sides get the same width, so the gap stays centered on the notch whatever its size.
    private var header: some View {
        let padding = vm.settings.layout.contentPadding
        let side = max(0, (vm.openSize.width - 2 * padding - vm.headerNotchGap) / 2)
        return HStack(spacing: 0) {
            HStack(spacing: NotchViewModel.headerSpacing) {
                ForEach(vm.visibleTabs) { tab in
                    HeaderButton(symbol: tab.symbol, isSelected: vm.tab == tab, help: tab.title) {
                        vm.tab = tab
                    }
                }
                if vm.tray.isLoading {
                    ProgressView().controlSize(.mini)
                }
            }
            .frame(width: side, alignment: .leading)

            Color.clear.frame(width: vm.headerNotchGap)

            HStack(spacing: NotchViewModel.headerSpacing) {
                if vm.pomodoro.isActive, vm.tab != .nook || !vm.settings.widgets.enabled.contains(.pomodoro) {
                    Text(vm.pomodoro.remainingText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(vm.pomodoro.phase.color)
                }
                HeaderButton(symbol: "gearshape.fill", isSelected: false, help: "Settings") {
                    vm.close()
                    SettingsWindowController.shared.show()
                }
            }
            .frame(width: side, alignment: .trailing)
        }
    }
}

struct HeaderButton: View {
    let symbol: String
    let isSelected: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(hovering ? 0.85 : 0.5))
                .frame(width: NotchViewModel.headerButtonSize.width, height: NotchViewModel.headerButtonSize.height)
                .background(
                    Capsule().fill(.white.opacity(isSelected ? 0.18 : (hovering ? 0.08 : 0)))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The widgets page: enabled widgets side by side, in the user's order.
struct NookView: View {
    let vm: NotchViewModel

    var body: some View {
        let widgets = vm.settings.widgets.enabled
        let spacing = vm.settings.layout.widgetSpacing
        if widgets.isEmpty {
            EmptyStateView(symbol: "square.grid.2x2", text: "Turn on widgets in Settings → Widgets")
        } else {
            GeometryReader { geo in
                let widths = widgetWidths(widgets, in: geo.size, spacing: spacing)
                HStack(spacing: spacing) {
                    ForEach(Array(widgets.enumerated()), id: \.element) { index, kind in
                        if index > 0, vm.settings.layout.showDividers {
                            Divider().overlay(.white.opacity(0.12))
                        }
                        widget(kind)
                            .frame(width: widths[index], height: geo.size.height)
                            .clipped()
                    }
                }
            }
        }
    }

    /// Explicit widths so the row always fits exactly: fixed-width widgets (Mirror)
    /// get their width, the rest share what's left by weight. (Flexible min widths overflowed.)
    private func widgetWidths(_ widgets: [WidgetKind], in size: CGSize, spacing: CGFloat) -> [CGFloat] {
        let dividers = vm.settings.layout.showDividers ? widgets.count - 1 : 0
        let gaps = widgets.count - 1 + dividers
        let available = size.width - CGFloat(gaps) * spacing - CGFloat(dividers)
        let fixed = widgets.map { vm.fixedWidth(of: $0, rowHeight: size.height).map { min($0, available / CGFloat(widgets.count)) } }
        let free = max(0, available - fixed.compactMap { $0 }.reduce(0, +))
        let totalWeight = zip(widgets, fixed).filter { $1 == nil }.map { weight($0.0) }.reduce(0, +)
        return zip(widgets, fixed).map { kind, fixed in
            fixed ?? free * weight(kind) / max(totalWeight, 0.01)
        }
    }

    private func weight(_ kind: WidgetKind) -> CGFloat {
        switch kind {
        case .media: 1.5
        case .pomodoro: 1.2
        case .calendar, .shortcuts: 1
        case .mirror: 0 // fixed width
        }
    }

    @ViewBuilder private func widget(_ kind: WidgetKind) -> some View {
        switch kind {
        case .media: MediaWidget(model: vm.nowPlaying)
        case .calendar: CalendarWidget()
        case .shortcuts: ShortcutsWidget()
        case .mirror: MirrorWidget()
        case .pomodoro: PomodoroWidget(timer: vm.pomodoro)
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 18))
            Text(text).font(.system(size: 11, weight: .medium, design: .rounded)).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.45))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
