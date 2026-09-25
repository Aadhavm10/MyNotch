import Foundation
import Observation

/// Lists and runs Siri Shortcuts through the `shortcuts` command-line tool.
@Observable
final class ShortcutsService {
    static let shared = ShortcutsService()

    private(set) var all: [String] = []
    private(set) var running: Set<String> = []
    private(set) var failed: Set<String> = []

    private let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")

    private init() { reload() }

    func reload() {
        DispatchQueue.global(qos: .utility).async {
            let output = self.runTool(["list"]).output
            let names = output
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            DispatchQueue.main.async { self.all = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
        }
    }

    func run(_ name: String) {
        guard !running.contains(name) else { return }
        running.insert(name)
        failed.remove(name)
        DispatchQueue.global(qos: .userInitiated).async {
            let status = self.runTool(["run", name]).status
            DispatchQueue.main.async {
                self.running.remove(name)
                if status != 0 { self.failed.insert(name) }
            }
        }
    }

    private func runTool(_ args: [String]) -> (output: String, status: Int32) {
        let process = Process()
        process.executableURL = tool
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return ("", -1) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus)
    }
}
