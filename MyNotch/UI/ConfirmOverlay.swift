import SwiftUI

/// Inline "are you sure?" card laid over notch content. Used instead of an alert, which would
/// steal focus from the non-activating notch panel.
struct ConfirmOverlay: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.85)))
    }
}
