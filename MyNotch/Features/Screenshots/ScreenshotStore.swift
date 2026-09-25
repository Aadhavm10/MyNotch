import AppKit
import Observation

struct Screenshot: Identifiable, Hashable {
    let url: URL
    let date: Date
    var id: URL { url }
    var isRecording: Bool { ["mov", "mp4"].contains(url.pathExtension.lowercased()) }
}

/// Recent screenshots and screen recordings from the folder macOS saves them to.
///
/// Watches that folder directly and keeps files carrying the `kMDItemIsScreenCapture` attribute
/// that macOS stamps on every capture, so it works whatever language the file names are in.
/// (A Spotlight query would be simpler, but Spotlight silently hides results in protected folders
/// like Desktop and Downloads from apps that haven't been granted access, and never prompts.)
@Observable
final class ScreenshotStore {
    static let shared = ScreenshotStore()

    private(set) var items: [Screenshot] = []
    /// The newest capture, set for a few seconds after it's taken (drives the closed-notch flash).
    private(set) var justCaptured: Screenshot?
    /// Set when macOS privacy settings block reading the screenshot folder.
    private(set) var accessDenied = false
    private(set) var directory: URL = ScreenshotStore.currentDirectory()

    private static let captureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"

    private let settings = SettingsStore.shared
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var watchedDirectory: URL?
    @ObservationIgnored private var knownURLs: Set<URL> = []
    @ObservationIgnored private var didInitialScan = false
    @ObservationIgnored private var pendingScan: DispatchWorkItem?
    @ObservationIgnored private var flashWork: DispatchWorkItem?
    @ObservationIgnored private var refreshTimer: Timer?
    /// Folder access happens here: the first read of Desktop/Downloads waits on macOS's privacy
    /// prompt, which would otherwise freeze the notch until it's answered.
    @ObservationIgnored private let io = DispatchQueue(label: "MyNotch.screenshots", qos: .utility)

    private init() {
        // Picks up a changed screenshot location and ages items out of the time window.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.reload() }
        enabledChanged()
    }

    /// The folder set in the Screenshot app's Options (defaults to the Desktop).
    static func currentDirectory() -> URL {
        let fallback = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        guard let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
              !location.isEmpty
        else { return fallback }
        let url = URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue ? url : fallback
    }

    /// Called when the shelf is turned on or off in Settings.
    func enabledChanged() {
        if settings.screenshots.enabled {
            reload()
        } else {
            stopWatching()
            items = []
            knownURLs = []
            didInitialScan = false
        }
    }

    func reload() {
        guard settings.screenshots.enabled else { return }
        directory = Self.currentDirectory()
        if watchedDirectory != directory { watch(directory) }
        scan(announceNew: false)
    }

    // MARK: Watching

    private func watch(_ directory: URL) {
        stopWatching()
        watchedDirectory = directory
        io.async { [weak self] in
            let fd = Darwin.open(directory.path, O_EVTONLY)
            guard fd >= 0 else { return }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in self?.scheduleScan() }
            source.setCancelHandler { close(fd) }
            source.resume()
            DispatchQueue.main.async {
                // The folder may have changed (or the shelf been turned off) while we waited.
                guard let self, self.watchedDirectory == directory, self.watcher == nil else {
                    source.cancel()
                    return
                }
                self.watcher = source
            }
        }
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
        watchedDirectory = nil
    }

    /// Folder events arrive in bursts (macOS writes a temp file, then renames it); scan once they settle.
    private func scheduleScan() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan(announceNew: true) }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private enum ScanResult {
        case found([Screenshot])
        case denied
        case failed
    }

    private func scan(announceNew: Bool) {
        let directory = directory
        let maxAgeDays = settings.screenshots.maxAgeDays
        let maxItems = settings.screenshots.maxItems
        io.async { [weak self] in
            let result = Self.findScreenshots(in: directory, maxAgeDays: maxAgeDays, maxItems: maxItems)
            DispatchQueue.main.async {
                guard let self, self.directory == directory else { return }
                self.apply(result, announceNew: announceNew)
            }
        }
    }

    /// Runs on `io`.
    private static func findScreenshots(in directory: URL, maxAgeDays: Double, maxItems: Int) -> ScanResult {
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        } catch {
            return (error as NSError).code == NSFileReadNoPermissionError ? .denied : .failed
        }
        let cutoff = maxAgeDays > 0 ? Date.now.addingTimeInterval(-maxAgeDays * 86400) : .distantPast
        let found = contents
            .filter { isScreenCapture($0) }
            .compactMap { url -> Screenshot? in
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true else { return nil }
                let date = values?.creationDate ?? .distantPast
                return date >= cutoff ? Screenshot(url: url, date: date) : nil
            }
            .sorted { $0.date > $1.date }
            .prefix(maxItems)
        return .found(Array(found))
    }

    private func apply(_ result: ScanResult, announceNew: Bool) {
        guard case let .found(found) = result else {
            accessDenied = { if case .denied = result { return true } else { return false } }()
            items = []
            return
        }
        accessDenied = false

        let newest = found.first
        if announceNew, didInitialScan, let newest, !knownURLs.contains(newest.url),
           Date.now.timeIntervalSince(newest.date) < 30
        {
            flash(newest)
        }
        knownURLs = Set(found.map(\.url))
        items = found
        didInitialScan = true
    }

    private static func isScreenCapture(_ url: URL) -> Bool {
        getxattr(url.path, captureAttribute, nil, 0, 0, 0) >= 0
    }

    private func flash(_ shot: Screenshot) {
        guard settings.liveActivities.screenshots else { return }
        flashWork?.cancel()
        justCaptured = shot
        let work = DispatchWorkItem { [weak self] in self?.justCaptured = nil }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    // MARK: Actions

    func copy(_ shot: Screenshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // Both the file and the image, so it pastes into Finder, chats and image editors alike.
        var objects: [NSPasteboardWriting] = [shot.url as NSURL]
        if !shot.isRecording, let image = NSImage(contentsOf: shot.url) { objects.append(image) }
        pasteboard.writeObjects(objects)
    }

    func open(_ shot: Screenshot) { NSWorkspace.shared.open(shot.url) }

    func reveal(_ shot: Screenshot) { NSWorkspace.shared.activateFileViewerSelecting([shot.url]) }

    /// Moves the file to the Trash (recoverable), not a permanent delete.
    func trash(_ shot: Screenshot) {
        do {
            try FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
            items.removeAll { $0.url == shot.url }
            knownURLs.remove(shot.url)
            Thumbnailer.shared.forget(shot.url)
            if justCaptured?.url == shot.url { justCaptured = nil }
        } catch {
            NSSound.beep()
        }
    }

    /// Copies the screenshot into the Tray so it survives cleaning up the folder.
    func addToTray(_ shot: Screenshot) {
        TrayStore.shared.add(urls: [shot.url])
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }
}
