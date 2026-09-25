import AVFoundation
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $navigation.pane) { pane in
                Label(pane.title, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(170)
        } detail: {
            Group {
                switch navigation.pane {
                case .general: GeneralPane()
                case .layout: LayoutPane()
                case .widgets: WidgetsPane()
                case .pomodoro: PomodoroPane()
                case .tray: TrayPane()
                case .clipboard: ClipboardPane()
                case .screenshots: ScreenshotsPane()
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(navigation.pane.title)
        }
        .frame(minWidth: 640, minHeight: 500)
    }
}

// MARK: - Helpers

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = { "\(Int($0)) pt" }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Bindable private var settings = SettingsStore.shared
    @State private var loginStatus = SMAppService.mainApp.status

    var body: some View {
        Form {
            Section("Opening") {
                Picker("Open the notch on", selection: $settings.general.openMode) {
                    ForEach(OpenMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if settings.general.openMode == .hover {
                    SliderRow(title: "Hover delay", value: $settings.general.hoverDelay, range: 0 ... 1, step: 0.05) {
                        String(format: "%.2fs", $0)
                    }
                    SliderRow(title: "Close delay", value: $settings.general.closeDelay, range: 0 ... 1.5, step: 0.05) {
                        String(format: "%.2fs", $0)
                    }
                } else {
                    Text("Hovering makes the notch peek; click it to open, click outside to close.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Open the Tray when dragging files onto the notch", isOn: $settings.general.openTrayOnFileDrag)
                Toggle("Haptic feedback", isOn: $settings.general.haptics)
            }
            Section("Displays") {
                Toggle("Show a notch on screens without one", isOn: $settings.general.showOnNonNotchScreens)
                Text("On external displays a notch-shaped pill appears at the top of the active screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Live Activities (closed notch)") {
                Toggle("Now Playing (album art + visualizer)", isOn: $settings.liveActivities.media)
                SliderRow(title: "Hide after pausing for", value: $settings.liveActivities.hideMediaAfterPause, range: 0 ... 120, step: 5) {
                    "\(Int($0))s"
                }
                .disabled(!settings.liveActivities.media)
                Toggle("Pomodoro countdown", isOn: $settings.liveActivities.pomodoro)
                Toggle("Tray file count", isOn: $settings.liveActivities.trayCount)
                Toggle("Flash new screenshots", isOn: $settings.liveActivities.screenshots)
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.general.launchAtLogin)
                    .onChange(of: settings.general.launchAtLogin) { loginStatus = SMAppService.mainApp.status }
                if loginStatus == .requiresApproval {
                    Button("Approve in System Settings → Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
        }
    }
}

// MARK: - Layout

private struct LayoutPane: View {
    @Bindable private var settings = SettingsStore.shared
    @Bindable private var vm = NotchWindowManager.shared.viewModel

    var body: some View {
        Form {
            Section {
                Toggle("Keep the notch open while editing", isOn: $vm.pinned)
                Picker("Preview tab", selection: $vm.tab) {
                    ForEach(NotchTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!vm.pinned)
            }
            Section("Nook (widgets)") {
                SliderRow(title: "Width", value: $settings.layout.nookWidth, range: 380 ... 1000, step: 10)
                SliderRow(title: "Height", value: $settings.layout.nookHeight, range: 120 ... 400, step: 5)
                SliderRow(title: "Widget spacing", value: $settings.layout.widgetSpacing, range: 0 ... 32)
                Toggle("Dividers between widgets", isOn: $settings.layout.showDividers)
            }
            Section("Tray") {
                SliderRow(title: "Width", value: $settings.layout.trayWidth, range: 320 ... 1000, step: 10)
                SliderRow(title: "Height", value: $settings.layout.trayHeight, range: 120 ... 400, step: 5)
            }
            Section("Shape") {
                SliderRow(title: "Content padding", value: $settings.layout.contentPadding, range: 4 ... 32)
                SliderRow(title: "Corner radius", value: $settings.layout.cornerRadius, range: 8 ... 44)
                SliderRow(title: "Notch width fine-tune", value: $settings.layout.notchWidthFineTune, range: -40 ... 40)
                SliderRow(title: "Fake notch width", value: $settings.layout.fakeNotchWidth, range: 100 ... 300, step: 5)
            }
            Section {
                Button("Reset Layout to Defaults") { settings.resetLayout() }
            }
        }
    }
}

// MARK: - Widgets

private struct WidgetsPane: View {
    @Bindable private var settings = SettingsStore.shared
    private let shortcuts = ShortcutsService.shared
    private let calendar = CalendarService.shared
    private let camera = CameraService.shared

    var body: some View {
        Form {
            Section("Widgets in the Nook (in order)") {
                ForEach(WidgetKind.allCases.filter { $0 != .mirror }) { kind in
                    let index = settings.widgets.enabled.firstIndex(of: kind)
                    HStack {
                        Toggle(isOn: Binding(
                            get: { index != nil },
                            set: { on in
                                if on { settings.widgets.enabled.append(kind) } else { settings.widgets.enabled.removeAll { $0 == kind } }
                            }
                        )) {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                        Spacer()
                        if let index {
                            Text("#\(index + 1)").foregroundStyle(.secondary).monospacedDigit()
                            Button { move(kind, by: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(index == 0)
                            Button { move(kind, by: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(!canMove(at: index, by: 1))
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section("Calendar") {
                if calendar.hasAccess {
                    Stepper("Show the next \(settings.widgets.calendarDaysAhead) day(s)", value: $settings.widgets.calendarDaysAhead, in: 1 ... 14)
                    ForEach(calendar.calendars, id: \.calendarIdentifier) { cal in
                        Toggle(isOn: calendarBinding(cal.calendarIdentifier)) {
                            HStack {
                                Circle().fill(Color(cgColor: cal.cgColor)).frame(width: 8, height: 8)
                                Text(cal.title)
                            }
                        }
                    }
                } else {
                    Button("Allow Calendar Access") { calendar.requestAccess() }
                }
            }
            .onChange(of: settings.widgets.calendarIDs) { calendar.refresh() }
            .onChange(of: settings.widgets.calendarDaysAhead) { calendar.refresh() }

            Section {
                SliderRow(title: "Button width", value: $settings.widgets.shortcutButtonWidth, range: 70 ... 220, step: 5)
                if shortcuts.all.isEmpty {
                    Text("No shortcuts found. Create some in the Shortcuts app.").foregroundStyle(.secondary)
                }
                ForEach(shortcuts.all, id: \.self) { name in
                    Toggle(name, isOn: Binding(
                        get: { settings.widgets.shortcuts.contains(name) },
                        set: { on in
                            if on { settings.widgets.shortcuts.append(name) } else { settings.widgets.shortcuts.removeAll { $0 == name } }
                        }
                    ))
                }
            } header: {
                HStack {
                    Text("Shortcuts")
                    Spacer()
                    Button("Reload") { shortcuts.reload() }.controlSize(.small)
                }
            }

            Section("Mirror") {
                Toggle(isOn: Binding(
                    get: { settings.widgets.enabled.contains(.mirror) },
                    set: { on in
                        settings.widgets.enabled.removeAll { $0 == .mirror }
                        if on { settings.widgets.enabled.append(.mirror) }
                    }
                )) {
                    Label("Show Mirror in the Nook", systemImage: WidgetKind.mirror.symbol)
                }
                if settings.widgets.enabled.contains(.mirror) {
                    Picker("Camera", selection: $settings.widgets.mirrorDeviceID) {
                        Text("Default").tag(String?.none)
                        ForEach(camera.devices, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(Optional(device.uniqueID))
                        }
                    }
                    Toggle("Start the camera automatically when the Nook opens", isOn: $settings.widgets.mirrorAutoStart)
                    Text("Otherwise, click the Mirror widget to turn the camera on. It always turns off when the notch closes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onAppear { camera.refreshDevices() }
        }
    }

    private func move(_ kind: WidgetKind, by offset: Int) {
        guard let index = settings.widgets.enabled.firstIndex(of: kind) else { return }
        let target = index + offset
        guard canMove(at: index, by: offset) else { return }
        settings.widgets.enabled.swapAt(index, target)
    }

    /// Mirror always stays last (it has its own toggle below), so nothing swaps past it.
    private func canMove(at index: Int, by offset: Int) -> Bool {
        let enabled = settings.widgets.enabled
        return enabled.indices.contains(index + offset) && enabled[index + offset] != .mirror
    }

    private func calendarBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { settings.widgets.calendarIDs.isEmpty || settings.widgets.calendarIDs.contains(id) },
            set: { on in
                var ids = settings.widgets.calendarIDs.isEmpty
                    ? calendar.calendars.map(\.calendarIdentifier)
                    : settings.widgets.calendarIDs
                if on { ids.append(id) } else { ids.removeAll { $0 == id } }
                // Everything selected is stored as "all" so new calendars show up automatically.
                let all = Set(calendar.calendars.map(\.calendarIdentifier))
                settings.widgets.calendarIDs = Set(ids) == all ? [] : Array(Set(ids))
            }
        )
    }
}

// MARK: - Pomodoro

private struct PomodoroPane: View {
    @Bindable private var settings = SettingsStore.shared
    private let timer = PomodoroTimer.shared
    private let sounds = ["Glass", "Hero", "Ping", "Pop", "Purr", "Submarine", "Blow", "Bottle", "Funk", "Morse", "Sosumi", "Tink", "Basso", "Frog"]

    var body: some View {
        Form {
            Section("Durations") {
                SliderRow(title: "Focus", value: $settings.pomodoro.workMinutes, range: 1 ... 90) { "\(Int($0)) min" }
                SliderRow(title: "Short break", value: $settings.pomodoro.shortBreakMinutes, range: 1 ... 30) { "\(Int($0)) min" }
                SliderRow(title: "Long break", value: $settings.pomodoro.longBreakMinutes, range: 1 ... 60) { "\(Int($0)) min" }
                Stepper("Long break after \(settings.pomodoro.roundsBeforeLongBreak) focus sessions",
                        value: $settings.pomodoro.roundsBeforeLongBreak, in: 1 ... 12)
            }
            Section("Flow") {
                Toggle("Start breaks automatically", isOn: $settings.pomodoro.autoStartBreaks)
                Toggle("Start focus sessions automatically", isOn: $settings.pomodoro.autoStartWork)
            }
            Section("Alerts") {
                Toggle("Play a sound when a phase ends", isOn: $settings.pomodoro.playSound)
                HStack {
                    Picker("Sound", selection: $settings.pomodoro.soundName) {
                        ForEach(sounds, id: \.self) { Text($0).tag($0) }
                    }
                    Button { NSSound(named: settings.pomodoro.soundName)?.play() } label: { Image(systemName: "speaker.wave.2") }
                        .buttonStyle(.borderless)
                }
                .disabled(!settings.pomodoro.playSound)
                Toggle("Show a notification", isOn: $settings.pomodoro.notify)
            }
            Section("Stats") {
                Stepper("Daily goal: \(settings.pomodoro.dailyGoal) sessions", value: $settings.pomodoro.dailyGoal, in: 1 ... 24)
                LabeledContent("Completed today", value: "\(timer.stats.todayCount)")
                LabeledContent("Last 7 days", value: "\(timer.stats.history(days: 7).map(\.count).reduce(0, +))")
                Button("Reset Stats", role: .destructive) { timer.stats.resetAll() }
            }
        }
        .onChange(of: settings.pomodoro) { timer.settingsChanged() }
    }
}

// MARK: - Tray

private struct TrayPane: View {
    @Bindable private var settings = SettingsStore.shared
    private let tray = TrayStore.shared

    var body: some View {
        Form {
            Section("Storage") {
                Picker("Keep files for", selection: $settings.tray.keepDays) {
                    Text("Forever").tag(0.0)
                    Text("1 day").tag(1.0)
                    Text("3 days").tag(3.0)
                    Text("1 week").tag(7.0)
                    Text("30 days").tag(30.0)
                }
                .onChange(of: settings.tray.keepDays) { tray.cleanExpired() }
                Text("Dropped files are copied into MyNotch's storage, so the originals can be moved or deleted.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Files in tray", value: "\(tray.items.count)")
                HStack {
                    Button("Show Storage Folder") { NSWorkspace.shared.open(TrayStore.storageDirectory) }
                    Button("Clear Tray", role: .destructive) { tray.removeAll() }
                        .disabled(tray.items.isEmpty)
                }
            }
        }
    }
}

// MARK: - Clipboard

private struct ClipboardPane: View {
    @Bindable private var settings = SettingsStore.shared
    private let store = ClipboardStore.shared
    @State private var confirmingClear = false

    var body: some View {
        Form {
            Section {
                Toggle("Keep clipboard history", isOn: $settings.clipboard.enabled)
                Toggle("Remember history after quitting", isOn: $settings.clipboard.persist)
                    .onChange(of: settings.clipboard.persist) { store.persistenceChanged() }
                Picker("Keep the last", selection: $settings.clipboard.maxItems) {
                    ForEach([20, 50, 100, 200], id: \.self) { Text("\($0) items").tag($0) }
                }
                .onChange(of: settings.clipboard.maxItems) { store.sortAndTrim() }
                Text("Pinned items don't count toward the limit and are never removed automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    LabeledContent("Items", value: "\(store.items.count)")
                    Spacer()
                    Button("Clear History…", role: .destructive) { confirmingClear = true }
                        .disabled(store.items.isEmpty)
                }
            }

            Section {
                ForEach(settings.clipboard.ignoredBundleIDs, id: \.self) { id in
                    HStack {
                        if let icon = AppIcons.icon(for: id) {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        }
                        Text(appName(id))
                        Spacer()
                        Button { settings.clipboard.ignoredBundleIDs.removeAll { $0 == id } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add App…", action: addIgnoredApp)
            } header: {
                Text("Never record copies from")
            } footer: {
                Text("Passwords that password managers mark as private are always skipped.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmingClear) {
            Button("Clear All but Pinned", role: .destructive) { store.removeAll() }
            Button("Clear Everything", role: .destructive) { store.removeAll(includingPinned: true) }
        } message: {
            Text("This can't be undone.")
        }
    }

    /// Installed app name for a bundle ID, or the ID itself when the app isn't installed.
    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func addIgnoredApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !settings.clipboard.ignoredBundleIDs.contains(id) {
                settings.clipboard.ignoredBundleIDs.append(id)
            }
        }
    }
}

// MARK: - Screenshots

private struct ScreenshotsPane: View {
    @Bindable private var settings = SettingsStore.shared
    private let store = ScreenshotStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show the screenshot shelf", isOn: $settings.screenshots.enabled)
                    .onChange(of: settings.screenshots.enabled) { store.enabledChanged() }
                Picker("Show up to", selection: $settings.screenshots.maxItems) {
                    ForEach([10, 20, 50], id: \.self) { Text("\($0) screenshots").tag($0) }
                }
                Picker("From the last", selection: $settings.screenshots.maxAgeDays) {
                    Text("Day").tag(1.0)
                    Text("Week").tag(7.0)
                    Text("Month").tag(30.0)
                    Text("Any time").tag(0.0)
                }
                Toggle("Flash new screenshots in the closed notch", isOn: $settings.liveActivities.screenshots)
            } footer: {
                Text("Shows screenshots and screen recordings from \(store.directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")), the folder set in the Screenshot app's Options (⇧⌘5). Nothing is copied or moved; \"Move to Trash\" can be undone from the Trash.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onChange(of: settings.screenshots.maxItems) { store.reload() }
            .onChange(of: settings.screenshots.maxAgeDays) { store.reload() }
        }
    }
}

// MARK: - About

private struct AboutPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("MyNotch", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                Text("A personal notch utility inspired by NotchNook.")
                    .foregroundStyle(.secondary)
            }
            Section("Open-source code used") {
                Link("NotchDrop — MIT, © 2024 Lakr Aream", destination: URL(string: "https://github.com/Lakr233/NotchDrop")!)
                Link("DynamicNotchKit — MIT, © 2025 Kai Azim", destination: URL(string: "https://github.com/MrKai77/DynamicNotchKit")!)
                Link("mediaremote-adapter — BSD-3-Clause, © Jonas van den Berg", destination: URL(string: "https://github.com/ungive/mediaremote-adapter")!)
            }
        }
    }
}
