import AppKit
import Observation

/// Runs conversions in the background, saves results next to the originals and hands them to the Tray.
@Observable
final class ConvertService {
    static let shared = ConvertService()

    /// Conversions still running; drives the closed notch's spinner.
    private(set) var activeCount = 0

    private init() {}

    /// Converts each file (or all of them together, for formats that combine inputs).
    /// Files in one request run one after another; separate requests run side by side.
    func convert(_ urls: [URL], to format: ConvertFormat) {
        guard !urls.isEmpty else { return }
        let groups = format.combinesInputs ? [urls] : urls.map { [$0] }
        activeCount += groups.count
        Task.detached(priority: .userInitiated) {
            var outputs: [URL] = []
            var failed = false
            for group in groups {
                let output = Self.outputURL(for: group, format: format)
                do {
                    try await Converter.run(group, to: format, output: output)
                    outputs.append(output)
                } catch {
                    failed = true
                    NSLog("MyNotch: convert to \(format.rawValue) failed: \(error.localizedDescription)")
                }
                await MainActor.run { self.activeCount -= 1 }
            }
            let converted = outputs, anyFailed = failed
            await MainActor.run {
                if SettingsStore.shared.convert.addToTray, !converted.isEmpty {
                    TrayStore.shared.add(urls: converted)
                }
                if anyFailed { NSSound.beep() }
            }
        }
    }

    /// Item providers from a drop: resolved off the main thread, like the Tray does.
    func convert(_ providers: [NSItemProvider], to format: ConvertFormat) {
        DispatchQueue.global(qos: .userInitiated).async {
            let urls = providers.compactMap { TrayStore.fileURL(from: $0) }
            DispatchQueue.main.async {
                if urls.count < providers.count { NSSound.beep() }
                self.convert(urls, to: format)
            }
        }
    }

    // MARK: Output location

    /// Next to the first source with a free name; PDF pages get a folder instead of a file.
    private static func outputURL(for sources: [URL], format: ConvertFormat) -> URL {
        let first = sources[0]
        var name = first.deletingPathExtension().lastPathComponent
        if format == .mergePDF { name += " merged" }
        let isFolder = ConvertInput(first)?.kind == .pdf && [.png, .jpg].contains(format) && pageCount(first) > 1
        return uniqueURL(in: outputDirectory(for: first), name: isFolder ? name + " pages" : name, ext: isFolder ? nil : format.fileExtension)
    }

    /// The source's folder, unless it's MyNotch's own storage or a temp folder (Tray items, browser
    /// drops) or not writable — then Downloads.
    private static func outputDirectory(for source: URL) -> URL {
        let dir = source.deletingLastPathComponent()
        let resolved = dir.resolvingSymlinksInPath().path
        let ownFolders = [TrayStore.rootDirectory, FileManager.default.temporaryDirectory]
            .map { $0.resolvingSymlinksInPath().path }
        if ownFolders.contains(where: { resolved.hasPrefix($0) }) || !FileManager.default.isWritableFile(atPath: dir.path) {
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
        return dir
    }

    /// "photo.png", then "photo 2.png", "photo 3.png"…
    private static func uniqueURL(in dir: URL, name: String, ext: String?) -> URL {
        func candidate(_ n: Int) -> URL {
            let base = n == 1 ? name : "\(name) \(n)"
            let url = dir.appendingPathComponent(base)
            return ext.map { url.appendingPathExtension($0) } ?? url
        }
        var n = 1
        while FileManager.default.fileExists(atPath: candidate(n).path) { n += 1 }
        return candidate(n)
    }

    private static func pageCount(_ url: URL) -> Int {
        CGPDFDocument(url as CFURL)?.numberOfPages ?? 0
    }
}
