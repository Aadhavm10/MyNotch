import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Output formats offered by the donut, the Tray's format strip and "Convert to…".
/// Formats marked `needsFFmpeg` only show up when Homebrew's ffmpeg is installed.
enum ConvertFormat: String, CaseIterable, Identifiable {
    case jpg, png, heic, tiff, webp, pdf, mergePDF, docx, txt, md, mp4, mov, webm, gif, m4a, mp3, wav
    var id: String { rawValue }

    var title: String {
        switch self {
        case .mergePDF: "Merge PDF"
        case .docx: "Word"
        case .txt: "Text"
        case .md: "Markdown"
        default: rawValue.uppercased()
        }
    }

    var fileExtension: String {
        switch self {
        case .mergePDF: "pdf"
        default: rawValue
        }
    }

    var symbol: String {
        switch self {
        case .jpg, .png, .heic, .tiff, .webp: "photo"
        case .pdf: "doc.richtext"
        case .mergePDF: "doc.on.doc"
        case .docx: "doc.text"
        case .txt: "doc.plaintext"
        case .md: "number"
        case .mp4, .mov, .webm: "film"
        case .gif: "play.rectangle.on.rectangle"
        case .m4a, .mp3, .wav: "waveform"
        }
    }

    var needsFFmpeg: Bool { [.webp, .webm, .mp3].contains(self) }

    /// Every input file goes into one output (several images → one PDF, several PDFs → one PDF).
    var combinesInputs: Bool { self == .pdf || self == .mergePDF }

    /// Extensions that already are this format, so converting to it would be a no-op.
    var sameFormatExtensions: Set<String> {
        switch self {
        case .jpg: ["jpg", "jpeg"]
        case .tiff: ["tif", "tiff"]
        case .heic: ["heic", "heif"]
        case .md: ["md", "markdown"]
        case .mergePDF: []
        default: [fileExtension]
        }
    }

    // MARK: Targets

    /// Formats every one of these files can be converted to, in display order.
    static func targets(for urls: [URL]) -> [ConvertFormat] {
        guard !urls.isEmpty else { return [] }
        let hasFFmpeg = FFmpeg.path != nil
        var result: [ConvertFormat]?
        for url in urls {
            guard let input = ConvertInput(url) else { return [] }
            let ext = url.pathExtension.lowercased()
            let formats = input.kind.targets(count: urls.count).filter { format in
                guard !format.sameFormatExtensions.contains(ext) else { return false }
                // ffmpeg handles both the formats macOS can't write and inputs it can't read.
                return hasFFmpeg || (input.isNative && !format.needsFFmpeg)
            }
            result = result.map { $0.filter(formats.contains) } ?? formats
        }
        return result ?? []
    }

    /// Targets for a drag in progress. Browser images arrive as data without a file URL until
    /// they're dropped, so those get the image targets.
    static func targets(forDrag pasteboard: NSPasteboard) -> [ConvertFormat] {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        if !urls.isEmpty { return targets(for: urls) }
        let isImage = pasteboard.types?.contains { UTType($0.rawValue)?.conforms(to: .image) == true } ?? false
        guard isImage else { return [] }
        let hasFFmpeg = FFmpeg.path != nil
        return ConvertKind.image.targets(count: 1).filter { hasFFmpeg || !$0.needsFFmpeg }
    }
}

enum ConvertKind {
    case image, pdf, video, audio

    func targets(count: Int) -> [ConvertFormat] {
        switch self {
        case .image: [.jpg, .png, .heic, .tiff, .webp, .pdf]
        case .pdf: count > 1 ? [.png, .jpg, .docx, .txt, .md, .mergePDF] : [.png, .jpg, .docx, .txt, .md]
        case .video: [.mp4, .mov, .gif, .m4a, .webm, .mp3]
        case .audio: [.m4a, .wav, .mp3]
        }
    }
}

/// What kind of file this is, and whether macOS can read it without ffmpeg.
struct ConvertInput {
    let kind: ConvertKind
    let isNative: Bool

    init?(_ url: URL) {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .pdf) {
            kind = .pdf
            isNative = true
        } else if type.conforms(to: .image) {
            kind = .image
            isNative = Self.imageTypes.contains(type.identifier)
        } else if type.conforms(to: .movie) {
            kind = .video
            isNative = Self.audiovisualTypes.contains(type.identifier)
        } else if type.conforms(to: .audio) {
            kind = .audio
            isNative = Self.audiovisualTypes.contains(type.identifier)
        } else {
            return nil
        }
    }

    private static let imageTypes = Set(CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])
    private static let audiovisualTypes = Set(AVURLAsset.audiovisualTypes().map(\.rawValue))
}
