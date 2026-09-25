import AppKit
import Observation
import QuickLookThumbnailing

/// Generates and caches Quick Look thumbnails for files (tray items, screenshots).
@Observable
final class Thumbnailer {
    static let shared = Thumbnailer()

    private(set) var images: [URL: NSImage] = [:]
    @ObservationIgnored private var inFlight: Set<URL> = []

    func image(for item: TrayItem) -> NSImage {
        image(forFileAt: item.storageURL)
    }

    /// The cached thumbnail, or the file's icon while the thumbnail is generated.
    func image(forFileAt url: URL, size: CGFloat = 96) -> NSImage {
        if let image = images[url] { return image }
        request(url, size: size)
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func forget(_ url: URL) { images[url] = nil }

    private func request(_ url: URL, size: CGFloat) {
        guard !inFlight.contains(url) else { return }
        inFlight.insert(url)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(url)
                if let rep { self.images[url] = rep.nsImage }
            }
        }
    }
}
