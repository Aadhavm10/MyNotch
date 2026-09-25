import SwiftUI

/// The Clipboard tab: recent copies as cards. Click a card to copy it again.
struct ClipboardView: View {
    let vm: NotchViewModel
    private let store = ClipboardStore.shared
    @State private var confirmingClear = false

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(.white.opacity(0.03))
            .overlay { content.padding(8) }
    }

    @ViewBuilder private var content: some View {
        if !vm.settings.clipboard.enabled {
            EmptyStateView(symbol: "clipboard", text: "Clipboard history is off.\nTurn it on in Settings → Clipboard.")
        } else if store.items.isEmpty {
            EmptyStateView(symbol: "doc.on.clipboard", text: "Copy something and it'll show up here")
        } else {
            HStack(spacing: 8) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 6) {
                        ForEach(store.items) { item in
                            ClipCard(item: item, store: store)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.never)
                VStack(spacing: 6) {
                    TrayActionButton(symbol: "trash", help: "Clear history…") {
                        confirmingClear = true
                    }
                }
            }
            .overlay {
                if confirmingClear {
                    let count = store.items.filter { !$0.pinned }.count
                    ConfirmOverlay(
                        title: "Clear \(count) item\(count == 1 ? "" : "s") from clipboard history?",
                        message: "Pinned items are kept.",
                        confirmTitle: "Clear History",
                        onCancel: { confirmingClear = false },
                        onConfirm: {
                            confirmingClear = false
                            store.removeAll()
                        }
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: confirmingClear)
        }
    }
}

private struct ClipCard: View {
    let item: ClipItem
    let store: ClipboardStore
    @State private var hovering = false

    private let width: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(8)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(hovering ? 0.12 : 0.07)))
        .overlay(alignment: .topTrailing) {
            if hovering { hoverButtons.padding(4).transition(.opacity) }
        }
        .overlay {
            if store.lastCopiedID == item.id {
                Label("Copied", systemImage: "checkmark")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.green.opacity(0.75)))
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.15), value: store.lastCopiedID)
        .onTapGesture { store.copy(item) }
        .onDrag { dragProvider }
        .help("Click to copy")
        .contextMenu { menu }
    }

    // MARK: Preview

    @ViewBuilder private var preview: some View {
        switch item.kind {
        case .text:
            if let url = item.link {
                VStack(alignment: .leading, spacing: 3) {
                    Label(url.host ?? "Link", systemImage: "link")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                    Text(url.absoluteString)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(3)
                        .truncationMode(.middle)
                }
            } else if let color = item.color {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: color)).frame(width: 28, height: 28)
                    Text(item.text ?? "").font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(.white)
            } else {
                Text(item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(4)
            }
        case .image:
            ClipImage(url: item.imageURL)
        case .files:
            let paths = item.filePaths ?? []
            HStack(spacing: 6) {
                if let first = paths.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first))
                        .resizable()
                        .frame(width: 32, height: 32)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(paths.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if paths.count > 1 {
                        Text("+\(paths.count - 1) more")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if let icon = AppIcons.icon(for: item.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 12, height: 12)
            }
            Text(shortAge(item.date))
            Spacer(minLength: 0)
            if item.pinned {
                Image(systemName: "pin.fill").foregroundStyle(.orange)
            }
        }
        .font(.system(size: 9, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.45))
    }

    private var hoverButtons: some View {
        HStack(spacing: 2) {
            SmallIconButton(symbol: item.pinned ? "pin.slash.fill" : "pin.fill", help: item.pinned ? "Unpin" : "Pin") {
                store.togglePin(item)
            }
            SmallIconButton(symbol: "xmark", help: "Delete") { store.remove(item) }
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Copy") { store.copy(item) }
        Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
        if let url = item.link {
            Button("Open Link") { NSWorkspace.shared.open(url) }
        }
        if let paths = item.filePaths, !paths.isEmpty {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
            }
        }
        Divider()
        Button("Delete", role: .destructive) { store.remove(item) }
    }

    private var dragProvider: NSItemProvider {
        switch item.kind {
        case .text: NSItemProvider(object: (item.text ?? "") as NSString)
        case .image: item.imageURL.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider()
        case .files: item.filePaths?.first.flatMap { NSItemProvider(contentsOf: URL(fileURLWithPath: $0)) } ?? NSItemProvider()
        }
    }

    private func shortAge(_ date: Date) -> String {
        let seconds = Int(Date.now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86400)d"
        }
    }
}

/// A clipboard image, center-cropped; decoded once and cached.
private struct ClipImage: View {
    let url: URL?

    var body: some View {
        Color.clear
            .overlay {
                if let image = url.flatMap(ImageCache.image) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(.white.opacity(0.4))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private enum ImageCache {
    private static let cache = NSCache<NSURL, NSImage>()

    static func image(_ url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}

private struct SmallIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.black.opacity(hovering ? 0.8 : 0.55)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
