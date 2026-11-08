import AppKit
import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum ConvertError: LocalizedError {
    case unreadable(URL)
    case unsupported(URL, ConvertFormat)
    case writeFailed(URL)
    case ffmpegMissing
    case ffmpegFailed(String)
    case noText(URL)

    var errorDescription: String? {
        switch self {
        case let .unreadable(url): "Couldn't read \(url.lastPathComponent)"
        case let .unsupported(url, format): "Can't convert \(url.lastPathComponent) to \(format.title)"
        case let .writeFailed(url): "Couldn't write \(url.lastPathComponent)"
        case .ffmpegMissing: "This conversion needs ffmpeg (brew install ffmpeg)"
        case let .ffmpegFailed(message): "ffmpeg failed: \(message)"
        case let .noText(url): "\(url.lastPathComponent) has no text to extract (it may be a scan)"
        }
    }
}

/// Routes one conversion to the native converter, or to ffmpeg for formats macOS can't handle.
enum Converter {
    /// Converts `sources` (one file, or several for formats that combine inputs) into `output`.
    static func run(_ sources: [URL], to format: ConvertFormat, output: URL) async throws {
        guard let first = sources.first, let input = ConvertInput(first) else {
            throw ConvertError.unreadable(sources.first ?? output)
        }
        let quality = SettingsStore.shared.convert.imageQuality

        switch (input.kind, format) {
        case (.image, .pdf):
            try ImageConverter.makePDF(from: sources, to: output)
        case (.image, .webp):
            try await ImageConverter.viaPNG(first) { try await FFmpeg.run($0, to: format, output: output) }
        case (.image, _) where input.isNative:
            try ImageConverter.convert(first, to: format, output: output, quality: quality)
        case (.pdf, .mergePDF):
            try PDFConverter.merge(sources, to: output)
        case (.pdf, .png), (.pdf, .jpg):
            try PDFConverter.renderPages(of: first, to: format, output: output, quality: quality)
        case (.pdf, .docx), (.pdf, .txt), (.pdf, .md):
            try PDFText.convert(first, to: format, output: output)
        case (.video, _) where input.isNative && !format.needsFFmpeg,
             (.audio, _) where input.isNative && !format.needsFFmpeg:
            try await MediaConverter.convert(first, to: format, output: output)
        default:
            try await FFmpeg.run(first, to: format, output: output)
        }
    }
}

// MARK: - Images

enum ImageConverter {
    static func convert(_ source: URL, to format: ConvertFormat, output: URL, quality: Double) throws {
        guard let type = UTType(filenameExtension: format.fileExtension),
              let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let dest = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil)
        else { throw ConvertError.unsupported(source, format) }

        let index = CGImageSourceGetPrimaryImageIndex(src)
        var properties = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any] ?? [:]
        properties[kCGImageDestinationLossyCompressionQuality] = quality

        // JPEG has no alpha: flatten onto white, or transparent areas come out black.
        if format == .jpg,
           let image = CGImageSourceCreateImageAtIndex(src, index, nil),
           image.hasAlpha,
           let flat = image.flattened(onto: .white)
        {
            CGImageDestinationAddImage(dest, flat, properties as CFDictionary)
        } else {
            CGImageDestinationAddImageFromSource(dest, src, index, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw ConvertError.writeFailed(output) }
    }

    /// One PDF page per image, each sized to its image (upright, honoring EXIF orientation).
    static func makePDF(from sources: [URL], to output: URL) throws {
        guard let context = CGContext(output as CFURL, mediaBox: nil, nil) else {
            throw ConvertError.writeFailed(output)
        }
        for source in sources {
            guard let image = upright(source) else {
                context.closePDF()
                throw ConvertError.unreadable(source)
            }
            var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.beginPage(mediaBox: &box)
            context.draw(image, in: box)
            context.endPage()
        }
        context.closePDF()
    }

    /// Writes an upright temporary PNG, hands it to `body`, then deletes it (ffmpeg ignores EXIF orientation).
    static func viaPNG(_ source: URL, _ body: (URL) async throws -> Void) async throws {
        guard let image = upright(source) else { throw ConvertError.unreadable(source) }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: temp) }
        try write(image, to: temp, as: .png)
        try await body(temp)
    }

    /// Full-size image with its EXIF orientation applied.
    static func upright(_ source: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil) else { return nil }
        let index = CGImageSourceGetPrimaryImageIndex(src)
        let props = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any]
        let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1),
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, index, options as CFDictionary)
    }

    static func write(_ image: CGImage, to url: URL, as type: UTType, quality: Double = 0.9) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConvertError.writeFailed(url)
        }
        let props = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(dest, image, props)
        guard CGImageDestinationFinalize(dest) else { throw ConvertError.writeFailed(url) }
    }
}

private extension CGImage {
    var hasAlpha: Bool {
        ![.none, .noneSkipFirst, .noneSkipLast].contains(alphaInfo)
    }

    func flattened(onto color: CGColor) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(color)
        context.fill(rect)
        context.draw(self, in: rect)
        return context.makeImage()
    }
}

// MARK: - PDF

enum PDFConverter {
    static func merge(_ sources: [URL], to output: URL) throws {
        let merged = PDFDocument()
        for source in sources {
            guard let doc = PDFDocument(url: source) else { throw ConvertError.unreadable(source) }
            for i in 0 ..< doc.pageCount {
                if let page = doc.page(at: i) { merged.insert(page, at: merged.pageCount) }
            }
        }
        guard merged.write(to: output) else { throw ConvertError.writeFailed(output) }
    }

    /// One image per page at 2×. A single page writes `output`; several go into an `output` folder.
    static func renderPages(of source: URL, to format: ConvertFormat, output: URL, quality: Double) throws {
        guard let doc = PDFDocument(url: source), doc.pageCount > 0,
              let type = UTType(filenameExtension: format.fileExtension)
        else { throw ConvertError.unreadable(source) }

        let name = source.deletingPathExtension().lastPathComponent
        if doc.pageCount > 1 {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        }
        for i in 0 ..< doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .cropBox)
            let rotated = page.rotation % 180 != 0
            let size = CGSize(
                width: (rotated ? bounds.height : bounds.width) * 2,
                height: (rotated ? bounds.width : bounds.height) * 2
            )
            let thumbnail = page.thumbnail(of: size, for: .cropBox)
            guard let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw ConvertError.unreadable(source)
            }
            let url = doc.pageCount > 1
                ? output.appendingPathComponent("\(name) \(i + 1).\(format.fileExtension)")
                : output
            try ImageConverter.write(image, to: url, as: type, quality: quality)
        }
    }
}

// MARK: - Video and audio

enum MediaConverter {
    static func convert(_ source: URL, to format: ConvertFormat, output: URL) async throws {
        let asset = AVURLAsset(url: source)
        switch format {
        case .mp4: try await export(asset, to: output, as: .mp4, presets: [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality])
        case .mov: try await export(asset, to: output, as: .mov, presets: [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality])
        case .m4a: try await export(asset, to: output, as: .m4a, presets: [AVAssetExportPresetAppleM4A])
        case .wav: try writeWAV(source, to: output)
        case .gif: try await makeGIF(asset, to: output)
        default: throw ConvertError.unsupported(source, format)
        }
    }

    /// Tries each preset in order (passthrough first: no re-encode, so instant and lossless).
    private static func export(_ asset: AVURLAsset, to output: URL, as fileType: AVFileType, presets: [String]) async throws {
        for preset in presets {
            guard await AVAssetExportSession.compatibility(ofExportPreset: preset, with: asset, outputFileType: fileType),
                  let session = AVAssetExportSession(asset: asset, presetName: preset)
            else { continue }
            try? FileManager.default.removeItem(at: output)
            if #available(macOS 15, *) {
                if (try? await session.export(to: output, as: fileType)) != nil { return }
            } else {
                session.outputURL = output
                session.outputFileType = fileType
                await session.export()
                if session.status == .completed { return }
            }
        }
        try? FileManager.default.removeItem(at: output)
        throw ConvertError.unsupported(asset.url, fileType == .m4a ? .m4a : fileType == .mov ? .mov : .mp4)
    }

    /// 16-bit PCM WAV at the source's sample rate and channel count.
    private static func writeWAV(_ source: URL, to output: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let out = try AVAudioFile(forWriting: output, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65536) else {
            throw ConvertError.writeFailed(output)
        }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try out.write(from: buffer)
        }
    }

    static let gifFPS = 12.0
    static let gifMaxDuration = 30.0
    static let gifMaxSize: CGFloat = 480

    /// First `gifMaxDuration` seconds at `gifFPS`, at most `gifMaxSize` wide, looping forever.
    private static func makeGIF(_ asset: AVURLAsset, to output: URL) async throws {
        let duration = try await asset.load(.duration).seconds
        let length = min(duration.isFinite ? duration : 0, gifMaxDuration)
        let frameCount = max(1, Int(length * gifFPS))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: gifMaxSize, height: gifMaxSize)
        let tolerance = CMTime(seconds: 0.5 / gifFPS, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        guard let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw ConvertError.writeFailed(output)
        }
        let fileProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / gifFPS]]

        var added = 0
        for i in 0 ..< frameCount {
            let time = CMTime(seconds: Double(i) / gifFPS, preferredTimescale: 600)
            guard let frame = try? await generator.image(at: time).image else { continue }
            CGImageDestinationAddImage(dest, frame, frameProps as CFDictionary)
            added += 1
        }
        guard added > 0 else { throw ConvertError.unreadable(asset.url) }
        guard CGImageDestinationFinalize(dest) else { throw ConvertError.writeFailed(output) }
    }
}

// MARK: - ffmpeg (optional, from Homebrew)

enum FFmpeg {
    /// Homebrew's ffmpeg, if installed (Apple silicon, then Intel prefix).
    static var path: URL? {
        ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
    }

    static func arguments(for format: ConvertFormat) -> [String] {
        let gifFilter = "fps=\(Int(MediaConverter.gifFPS)),scale='min(\(Int(MediaConverter.gifMaxSize)),iw)':-2:flags=lanczos,"
            + "split[a][b];[a]palettegen[p];[b][p]paletteuse"
        return switch format {
        case .webp: ["-quality", "85"]
        case .mp3: ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
        case .webm: ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-c:a", "libopus"]
        case .mp4, .mov: ["-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "aac", "-movflags", "+faststart"]
        case .m4a: ["-vn", "-c:a", "aac", "-b:a", "192k"]
        case .wav: ["-vn", "-c:a", "pcm_s16le"]
        case .gif: ["-t", "\(Int(MediaConverter.gifMaxDuration))", "-vf", gifFilter, "-loop", "0"]
        case .jpg, .png, .heic, .tiff, .pdf, .mergePDF, .docx, .txt, .md: []
        }
    }

    static func run(_ source: URL, to format: ConvertFormat, output: URL) async throws {
        guard let path else { throw ConvertError.ffmpegMissing }
        let process = Process()
        process.executableURL = path
        process.arguments = ["-y", "-hide_banner", "-loglevel", "error", "-i", source.path]
            + arguments(for: format) + [output.path]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let data = stderr.fileHandleForReading.readDataToEndOfFile()
                    let message = String(decoding: data, as: UTF8.self)
                        .split(separator: "\n").last.map(String.init) ?? "exit \(process.terminationStatus)"
                    try? FileManager.default.removeItem(at: output)
                    continuation.resume(throwing: ConvertError.ffmpegFailed(message))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}
