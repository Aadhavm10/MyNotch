import SwiftUI

struct ShortcutsWidget: View {
    private let service = ShortcutsService.shared
    private let settings = SettingsStore.shared

    var body: some View {
        let names = settings.widgets.shortcuts
        if names.isEmpty {
            Button {
                SettingsWindowController.shared.show(pane: .widgets)
            } label: {
                EmptyStateView(symbol: "square.stack.3d.up", text: "Pick shortcuts in Settings")
            }
            .buttonStyle(.plain)
        } else {
            let width = settings.widgets.shortcutButtonWidth
            ScrollView(.vertical) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: width), spacing: 6)], spacing: 6) {
                    ForEach(names, id: \.self) { name in
                        ShortcutButton(
                            name: name,
                            isRunning: service.running.contains(name),
                            didFail: service.failed.contains(name)
                        ) { service.run(name) }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

private struct ShortcutButton: View {
    let name: String
    let isRunning: Bool
    let didFail: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Group {
                    if isRunning {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: didFail ? "exclamationmark.triangle.fill" : "play.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(didFail ? .orange : .white.opacity(0.8))
                    }
                }
                .frame(width: 14)
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(hovering ? 0.18 : 0.1)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(name)
    }
}
