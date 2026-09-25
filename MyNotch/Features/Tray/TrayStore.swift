// Adapted from NotchDrop's TrayDrop / DropItem / Ext+FileProvider
// (https://github.com/Lakr233/NotchDrop), MIT License, Copyright (c) 2024 Lakr Aream.

import AppKit
import CoreTransferable
import Observation
import UniformTypeIdentifiers

struct TrayItem: Identifiable, Codable, Hashable {
    let id: UUID
    let fileName: String
    let size: Int
    let dateAdded: Date

    var storageURL: URL {
        TrayStore.storageDirectory
            .appendingPathComponent(id.uuidString)
            .appendingPathComponent(fileName)
    }

    var exists: Bool { FileManager.default.fileExists(atPath: storageURL.path) }
}

extension TrayItem: Transferable {
    /// Drags out a temporary copy, so the receiver moving the file never empties the tray.
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(
            contentType: .item,
            shouldAttemptToOpenInPlace: true,
            exporting: { item in
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("MyNotchDrag")
                    .appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let copy = dir.appendingPathComponent(item.fileName)
                try FileManager.default.copyItem(at: item.storageURL, to: copy)
                return SentTransferredFile(copy, allowAccessingOriginalFile: true)
            },
            importing: { _ in throw CocoaError(.featureUnsupported) }
        )
    }
}

/// Files staged in the notch. Dropped files are copied into Application Support and indexed in tray.json.
@Observable
final class TrayStore {
    static let shared = TrayStore()

    static let rootDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MyNotch")
    static let storageDirectory = rootDirectory.appendingPathComponent("Tray")
    private static let indexURL = rootDirectory.appendingPathComponent("tray.json")

    private(set) var items: [TrayItem] = []
    private(set) var loadingCount = 0
    var isLoading: Bool { loadingCount > 0 }

    private var cleanupTimer: Timer?

    private init() {
        try? FileManager.default.createDirectory(at: Self.storageDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: Self.indexURL),
           let saved = try? JSONDecoder().decode([TrayItem].self, from: data)
        {
            items = saved
        }
        cleanExpired()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.cleanExpired()
        }
    }

    // MARK: Adding

    func load(_ providers: [NSItemProvider]) {
        loadingCount += 1
        DispatchQueue.global(qos: .userInitiated).async {
            let urls = providers.compactMap { Self.fileURL(from: $0) }
            var added: [TrayItem] = []
            var failures = providers.count - urls.count
            for url in urls {
                do { added.append(try Self.copyIn(url)) } catch { failures += 1 }
            }
            DispatchQueue.main.async {
                self.items.insert(contentsOf: added, at: 0)
                self.loadingCount -= 1
                self.save()
                if failures > 0 { NSSound.beep() }
            }
        }
    }

    func add(urls: [URL]) {
        load(urls.compactMap { NSItemProvider(contentsOf: $0) })
    }

    /// Resolves a dragged item to a file URL (blocking; call off the main thread).
    private static func fileURL(from provider: NSItemProvider) -> URL? {
        var result: URL?
        let sem = DispatchSemaphore(value: 0)
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { result = url }
                sem.signal()
            }
            sem.wait()
        }
        if result == nil {
            // Promised or in-memory data (e.g. an image dragged from a browser).
            provider.loadFileRepresentation(forTypeIdentifier: UTType.data.identifier) { url, _ in
                defer { sem.signal() }
                guard let url else { return }
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathComponent(provider.suggestedName.map { $0 + "." + url.pathExtension } ?? url.lastPathComponent)
                try? FileManager.default.createDirectory(at: temp.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? FileManager.default.copyItem(at: url, to: temp)) != nil { result = temp }
            }
            sem.wait()
        }
        return result
    }

    private static func copyIn(_ url: URL) throws -> TrayItem {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        let item = TrayItem(
            id: UUID(),
            fileName: url.lastPathComponent,
            size: values?.fileSize ?? values?.totalFileAllocatedSize ?? 0,
            dateAdded: Date()
        )
        try FileManager.default.createDirectory(
            at: item.storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: url, to: item.storageURL)
        return item
    }

    // MARK: Removing

    func remove(_ item: TrayItem) {
        try? FileManager.default.removeItem(at: item.storageURL.deletingLastPathComponent())
        items.removeAll { $0.id == item.id }
        Thumbnailer.shared.forget(item.storageURL)
        save()
    }

    func removeAll() {
        items.forEach { try? FileManager.default.removeItem(at: $0.storageURL.deletingLastPathComponent()) }
        items.removeAll()
        save()
    }

    func cleanExpired() {
        let keepDays = SettingsStore.shared.tray.keepDays
        let expired = items.filter { item in
            !item.exists || (keepDays > 0 && Date().timeIntervalSince(item.dateAdded) > keepDays * 86400)
        }
        expired.forEach(remove)
    }

    // MARK: Actions

    func open(_ item: TrayItem) { NSWorkspace.shared.open(item.storageURL) }

    func revealInFinder(_ items: [TrayItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.storageURL))
    }

    func copyToPasteboard(_ items: [TrayItem]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items.map { $0.storageURL as NSURL })
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: Self.indexURL, options: .atomic)
    }
}
