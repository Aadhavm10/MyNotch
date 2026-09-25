import AVFoundation
import Observation

/// Webcam preview for the Mirror widget. The session only runs while the widget is on screen.
@Observable
final class CameraService {
    static let shared = CameraService()

    private(set) var isRunning = false
    private(set) var status: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var devices: [AVCaptureDevice] = []

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let queue = DispatchQueue(label: "MyNotch.camera")
    @ObservationIgnored private var configuredDeviceID: String?

    private init() { refreshDevices() }

    func refreshDevices() {
        devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.status = AVCaptureDevice.authorizationStatus(for: .video)
                    if granted { self.startSession() }
                }
            }
        default:
            status = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    func stop() {
        isRunning = false
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func startSession() {
        status = .authorized
        refreshDevices()
        let wantedID = SettingsStore.shared.widgets.mirrorDeviceID
        let device = devices.first { $0.uniqueID == wantedID }
            ?? AVCaptureDevice.default(for: .video)
            ?? devices.first
        guard let device else { return }
        isRunning = true
        queue.async {
            if self.configuredDeviceID != device.uniqueID {
                self.session.beginConfiguration()
                self.session.inputs.forEach { self.session.removeInput($0) }
                if let input = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                if self.session.canSetSessionPreset(.medium) { self.session.sessionPreset = .medium }
                self.session.commitConfiguration()
                self.configuredDeviceID = device.uniqueID
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }
}
