// Layout inspired by NotchDrop's TrayView / DropItemView (https://github.com/Lakr233/NotchDrop), MIT, Copyright (c) 2024 Lakr Aream.

import SwiftUI

struct TrayView: View {
    let vm: NotchViewModel
    private var store: TrayStore { vm.tray }
    /// Clearing deletes the tray's copies, so the trash button asks first (inline, since an alert
    /// would steal focus from the non-activating notch panel).
    @State private var confirmingClear = false

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(.white.opacity(vm.dropTargeting ? 0.5 : 0.15))
            .background(
                RoundedRectangle(cornerRadius: 14).fill(.white.opacity(vm.dropTargeting ? 0.08 : 0.03))
            )
            .overlay { content.padding(8) }
    }

    @ViewBuilder private var content: some View {
        if store.items.isEmpty {
            EmptyStateView(symbol: "tray.and.arrow.down.fill", text: "Drop files here to keep them handy")
        } else {
            HStack(spacing: 8) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 6) {
                        ForEach(store.items) { item in
                            TrayItemView(item: item, store: store)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollIndicators(.never)
                VStack(spacing: 6) {
                    TrayActionButton(symbol: "airplayaudio", help: "AirDrop all") {
                        Share.airDrop(store.items.map(\.storageURL))
                    }
                    TrayActionButton(symbol: "square.and.arrow.up", help: "Share all") {
                        Share.picker(store.items.map(\.storageURL))
                    }
                    TrayActionButton(symbol: "trash", help: "Clear tray…") {
                        confirmingClear = true
                    }
                }
            }
            .overlay {
                if confirmingClear { clearConfirmation.transition(.opacity) }
            }
            .animation(.easeOut(duration: 0.15), value: confirmingClear)
            .onChange(of: store.items.isEmpty) { _, empty in if empty { confirmingClear = false } }
        }
    }

    private var clearConfirmation: some View {
        let count = store.items.count
        return ConfirmOverlay(
            title: "Clear \(count) item\(count == 1 ? "" : "s") from the tray?",
            message: "Originals in Finder aren't affected.",
            confirmTitle: "Clear Tray",
            onCancel: { confirmingClear = false },
            onConfirm: {
                confirmingClear = false
                store.removeAll()
            }
        )
    }
}

private struct TrayItemView: View {
    let item: TrayItem
    let store: TrayStore
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: Thumbnailer.shared.image(for: item))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 52)
            Text(item.fileName)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 72)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(hovering ? 0.1 : 0)))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { store.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .gray.opacity(0.8))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .draggable(item) {
            Image(nsImage: Thumbnailer.shared.image(for: item)).resizable().frame(width: 48, height: 48)
        }
        .onTapGesture(count: 2) { store.open(item) }
        .help("\(item.fileName) · \(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))")
        .contextMenu {
            Button("Open") { store.open(item) }
            Button("Show in Finder") { store.revealInFinder([item]) }
            Button("Copy") { store.copyToPasteboard([item]) }
            Divider()
            Button("AirDrop…") { Share.airDrop([item.storageURL]) }
            Button("Share…") { Share.picker([item.storageURL]) }
            Divider()
            Button("Remove from Tray", role: .destructive) { store.remove(item) }
        }
    }
}

struct TrayActionButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(hovering ? 0.18 : 0.08)))
                .foregroundStyle(.white.opacity(0.85))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
