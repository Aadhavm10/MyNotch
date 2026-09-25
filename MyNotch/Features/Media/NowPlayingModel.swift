import AppKit
import Observation
import SwiftUI

/// Current "Now Playing" state from any app (Spotify, Music, Safari, Chrome, …).
@Observable
final class NowPlayingModel {
    static let shared = NowPlayingModel()

    private(set) var title: String?
    private(set) var artist: String?
    private(set) var album: String?
    private(set) var artwork: NSImage?
    private(set) var tint: Color = .white
    private(set) var isPlaying = false
    private(set) var duration: Double = 0
    private(set) var bundleID: String?
    /// Elapsed seconds as of `elapsedTimestamp`.
    private(set) var elapsed: Double = 0
    private(set) var elapsedTimestamp = Date()
    private(set) var playbackRate: Double = 1
    /// False once playback has been paused for longer than the live-activity timeout.
    private(set) var recentlyActive = false

    var hasTrack: Bool { title != nil }

    @ObservationIgnored private let adapter = MediaRemoteAdapter()
    @ObservationIgnored private var state: [String: Any] = [:]
    @ObservationIgnored private var inactivityWork: DispatchWorkItem?

    private init() {}

    func start() {
        adapter.onUpdate = { [weak self] diff, payload in self?.apply(diff: diff, payload: payload) }
        adapter.start()
    }

    func stop() { adapter.stop() }

    // MARK: Derived

    func currentElapsed(at date: Date = Date()) -> Double {
        var value = elapsed
        if isPlaying { value += date.timeIntervalSince(elapsedTimestamp) * playbackRate }
        return duration > 0 ? min(max(0, value), duration) : max(0, value)
    }

    var showsLiveActivity: Bool { hasTrack && (isPlaying || recentlyActive) }

    var sourceAppIcon: NSImage? {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: Controls

    func togglePlayPause() {
        adapter.send(.togglePlayPause)
        // Optimistic UI; the stream confirms shortly after.
        elapsed = currentElapsed()
        elapsedTimestamp = Date()
        isPlaying.toggle()
    }

    func next() { adapter.send(.next) }
    func previous() { adapter.send(.previous) }

    func seek(to seconds: Double) {
        adapter.seek(to: seconds)
        elapsed = seconds
        elapsedTimestamp = Date()
    }

    func openSourceApp() {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    // MARK: Stream handling

    private func apply(diff: Bool, payload: [String: Any]) {
        if diff {
            for (key, value) in payload {
                if value is NSNull { state.removeValue(forKey: key) } else { state[key] = value }
            }
        } else {
            state = payload
        }

        title = state["title"] as? String
        artist = (state["artist"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        album = state["album"] as? String
        bundleID = (state["parentApplicationBundleIdentifier"] as? String) ?? (state["bundleIdentifier"] as? String)
        duration = ((state["durationMicros"] as? NSNumber)?.doubleValue ?? 0) / 1_000_000
        playbackRate = (state["playbackRate"] as? NSNumber)?.doubleValue ?? 1
        if playbackRate <= 0 { playbackRate = 1 }

        if let micros = (state["elapsedTimeMicros"] as? NSNumber)?.doubleValue {
            elapsed = micros / 1_000_000
            if let ts = (state["timestampEpochMicros"] as? NSNumber)?.doubleValue {
                elapsedTimestamp = Date(timeIntervalSince1970: ts / 1_000_000)
            } else {
                elapsedTimestamp = Date()
            }
        }

        let playing = (state["playing"] as? Bool) ?? false
        if playing != isPlaying || !diff { setPlaying(playing) }

        if !diff || payload.keys.contains("artworkData") {
            if let base64 = state["artworkData"] as? String, let data = Data(base64Encoded: base64),
               let image = NSImage(data: data)
            {
                artwork = image
                tint = image.averageColor.map { Color(nsColor: $0) } ?? .white
            } else {
                artwork = nil
                tint = .white
            }
        }
    }

    private func setPlaying(_ playing: Bool) {
        isPlaying = playing
        inactivityWork?.cancel()
        if playing {
            recentlyActive = true
        } else {
            let work = DispatchWorkItem { [weak self] in self?.recentlyActive = false }
            inactivityWork = work
            let timeout = SettingsStore.shared.liveActivities.hideMediaAfterPause
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
        }
    }
}

extension NSImage {
    /// Average color, brightened so it reads well on black.
    var averageColor: NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let color = NSColor(
            red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1
        )
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(s * 1.2, 1), brightness: max(b, 0.75), alpha: 1)
    }
}
