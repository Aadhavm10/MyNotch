import AVFoundation
import SwiftUI

struct MirrorWidget: View {
    private let camera = CameraService.shared
    @State private var active = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.08))
            if active, camera.isRunning {
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .transition(.opacity)
            } else if camera.status == .denied || camera.status == .restricted {
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                } label: {
                    EmptyStateView(symbol: "video.slash", text: "Camera access denied")
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "person.crop.square").font(.system(size: 20))
                    Text("Mirror").font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.5))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .onAppear { if SettingsStore.shared.widgets.mirrorAutoStart { toggle() } }
        .onDisappear {
            active = false
            camera.stop()
        }
        .animation(.easeInOut(duration: 0.2), value: camera.isRunning)
        .help(active ? "Click to turn the camera off" : "Click to check your appearance")
    }

    private func toggle() {
        active.toggle()
        if active { camera.start() } else { camera.stop() }
    }
}

/// Mirrored AVCaptureVideoPreviewLayer.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        view.layer = layer
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        guard let layer = view.layer as? AVCaptureVideoPreviewLayer,
              let connection = layer.connection, connection.isVideoMirroringSupported,
              !connection.isVideoMirrored
        else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}
