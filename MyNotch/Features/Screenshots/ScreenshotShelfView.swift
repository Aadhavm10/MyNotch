import SwiftUI

/// The Screenshots tab: recent captures, newest first. Drag one into any app, or click to copy it.
struct ScreenshotShelfView: View {
    let vm: NotchViewModel
    private let store = ScreenshotStore.shared

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(.white.opacity(0.03))
            .overlay { content.padding(8) }
    }

    @ViewBuilder private var content: some View {
        if !vm.settings.screenshots.enabled {
            EmptyStateView(symbol: "camera.viewfinder", text: "The screenshot shelf is off.\nTurn it on in Settings → Screenshots.")
        } else if store.accessDenied {
            VStack(spacing: 8) {
                EmptyStateView(
                    symbol: "lock.fill",
                    text: "MyNotch needs access to your \(store.directory.lastPathComponent) folder to show screenshots."
                )
                .frame(maxHeight: 60)
                Button("Open Privacy Settings") { store.openPrivacySettings() }
                    .controlSize(.small)
            }
        } else if store.items.isEmpty {
            EmptyStateView(symbol: "camera.viewfinder", text: "Take a screenshot (⇧⌘4) and it'll show up here")
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(store.items) { shot in
                        ScreenshotCard(shot: shot, store: store)
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.never)
        }
    }
}

private struct ScreenshotCard: View {
    let shot: Screenshot
    let store: ScreenshotStore
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Color.clear
                .overlay {
                    Image(nsImage: Thumbnailer.shared.image(forFileAt: shot.url, size: 240))
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(alignment: .bottomLeading) {
                    if shot.isRecording {
                        Image(systemName: "video.fill")
                            .font(.system(size: 9, weight: .bold))
                            .padding(4)
                            .background(Circle().fill(.black.opacity(0.6)))
                            .padding(4)
                    }
                }
            Text(shortAge(shot.date))
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(6)
        .frame(width: 150)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(hovering ? 0.12 : 0.06)))
        .overlay(alignment: .topTrailing) {
            if hovering {
                HStack(spacing: 2) {
                    ShelfIconButton(symbol: "tray.and.arrow.down.fill", help: "Keep in Tray") { store.addToTray(shot) }
                    ShelfIconButton(symbol: "trash.fill", help: "Move to Trash") { store.trash(shot) }
                }
                .padding(9)
                .transition(.opacity)
            }
        }
        .overlay {
            if copied {
                Label("Copied", systemImage: "checkmark")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.green.opacity(0.75)))
                    .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.15), value: copied)
        .onTapGesture(count: 2) { store.open(shot) }
        .onTapGesture { copy() }
        .onDrag { NSItemProvider(contentsOf: shot.url) ?? NSItemProvider() }
        .help("\(shot.url.lastPathComponent)\nClick to copy · double-click to open · drag into any app")
        .contextMenu {
            Button("Copy") { copy() }
            Button("Open") { store.open(shot) }
            Button("Show in Finder") { store.reveal(shot) }
            Button("Keep in Tray") { store.addToTray(shot) }
            Divider()
            Button("Move to Trash", role: .destructive) { store.trash(shot) }
        }
    }

    private func copy() {
        store.copy(shot)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }

    private func shortAge(_ date: Date) -> String {
        let seconds = Int(Date.now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "Just now"
        case ..<3600: return "\(seconds / 60) min ago"
        case ..<86400: return "\(seconds / 3600) hr ago"
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

private struct ShelfIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.black.opacity(hovering ? 0.85 : 0.6)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
