import Foundation

/// Talks to the bundled mediaremote-adapter (ungive/mediaremote-adapter, BSD-3) through /usr/bin/perl,
/// which is still entitled to use MediaRemote on macOS 15.4+.
final class MediaRemoteAdapter {
    enum Command: Int {
        case play = 0, pause = 1, togglePlayPause = 2, stop = 3, next = 4, previous = 5
        case goBack15 = 12, skip15 = 13
    }

    /// Called on the main queue with every stream message: (isDiff, payload).
    var onUpdate: ((Bool, [String: Any]) -> Void)?

    private var process: Process?
    private var buffer = Data()
    private var stopped = false
    private var restartDelay: TimeInterval = 1

    private let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private var resources: URL? { Bundle.main.resourceURL?.appendingPathComponent("MediaRemoteAdapter") }
    private var script: String? { resources?.appendingPathComponent("mediaremote-adapter.pl").path }
    private var framework: String? { resources?.appendingPathComponent("MediaRemoteAdapter.framework").path }

    var isAvailable: Bool {
        guard let script, let framework else { return false }
        return FileManager.default.fileExists(atPath: script) && FileManager.default.fileExists(atPath: framework)
    }

    func start() {
        stopped = false
        killOrphanedStreams()
        launchStream()
    }

    func stop() {
        stopped = true
        process?.terminate()
        process = nil
    }

    func send(_ command: Command) {
        runOnce(["send", String(command.rawValue)])
    }

    func seek(to seconds: Double) {
        runOnce(["seek", String(Int(max(0, seconds) * 1_000_000))])
    }

    // MARK: Private

    /// If MyNotch was force-killed (Xcode stop, crash, `kill -9`), its adapter keeps running,
    /// re-parented to launchd. Those orphans have PPID 1, so live instances are never touched.
    private func killOrphanedStreams() {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-P", "1", "-f", "MediaRemoteAdapter/mediaremote-adapter.pl"]
        pkill.standardOutput = FileHandle.nullDevice
        pkill.standardError = FileHandle.nullDevice
        try? pkill.run()
        pkill.waitUntilExit()
    }

    private func launchStream() {
        guard isAvailable, let script, let framework else {
            NSLog("MyNotch: mediaremote-adapter not bundled; media controls disabled")
            return
        }
        let process = Process()
        process.executableURL = perl
        process.arguments = [script, framework, "stream", "--micros", "--debounce=40"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        buffer = Data()

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.consume(chunk)
        }
        process.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self, !self.stopped else { return }
                // Adapter died (e.g. after sleep); back off and restart.
                DispatchQueue.main.asyncAfter(deadline: .now() + self.restartDelay) { self.launchStream() }
                self.restartDelay = min(self.restartDelay * 2, 30)
            }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            NSLog("MyNotch: failed to launch adapter: \(error.localizedDescription)")
        }
    }

    /// Runs on the pipe's background queue; splits newline-delimited JSON.
    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex ..< newline)
            buffer.removeSubrange(buffer.startIndex ... newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = object["payload"] as? [String: Any]
            else { continue }
            let diff = object["diff"] as? Bool ?? false
            DispatchQueue.main.async { [weak self] in
                self?.restartDelay = 1
                self?.onUpdate?(diff, payload)
            }
        }
    }

    private func runOnce(_ args: [String]) {
        guard isAvailable, let script, let framework else { return }
        let process = Process()
        process.executableURL = perl
        process.arguments = [script, framework] + args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
