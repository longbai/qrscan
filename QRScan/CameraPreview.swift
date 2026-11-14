@preconcurrency import AVFoundation
import SwiftUI

struct CameraCode: Identifiable {
    let id: UUID
    let payload: String
    let bounds: CGRect
}

struct CameraPreview: UIViewControllerRepresentable {
    var isScanning: Bool
    var isTorchOn: Bool
    var onCodes: ([CameraCode]) -> Void
    var onUnavailable: () -> Void

    func makeUIViewController(context: Context) -> CameraController {
        CameraController()
    }

    func updateUIViewController(_ controller: CameraController, context: Context) {
        controller.onCodes = onCodes
        controller.onUnavailable = onUnavailable
        controller.updateCamera(scanning: isScanning, torch: isTorchOn)
    }

    static func dismantleUIViewController(_ controller: CameraController, coordinator: ()) {
        controller.updateCamera(scanning: false, torch: false)
    }
}

final class CameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private struct Detection {
        let code: CameraCode
        let timestamp: ContinuousClock.Instant
    }

    private let camera = CameraSession()
    private var isScanning = false
    private var isTorchOn = false
    private var detections: [Detection] = []
    private var expiry: Task<Void, Never>?
    private var previewBounds = CGRect.zero
    private var preview: PreviewView { view as! PreviewView }

    var onCodes: (([CameraCode]) -> Void)?
    var onUnavailable: (() -> Void)?

    override func loadView() {
        let preview = PreviewView()
        preview.backgroundColor = .black
        preview.previewLayer.videoGravity = .resizeAspectFill
        preview.previewLayer.session = camera.session
        view = preview
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if previewBounds != preview.bounds {
            previewBounds = preview.bounds
            expiry?.cancel()
            detections.removeAll()
        }
        updatePreviewRotation()
    }

    func updateCamera(scanning enabled: Bool, torch: Bool) {
        guard isScanning != enabled || isTorchOn != torch else { return }
        isScanning = enabled
        isTorchOn = torch
        if !enabled {
            expiry?.cancel()
            detections.removeAll()
        }
        camera.update(running: enabled, torch: torch, delegate: self) { [weak self] configured in
            guard let self else { return }
            if configured {
                self.updatePreviewRotation()
            } else if self.isScanning {
                self.onUnavailable?()
            }
        }
    }

    private func updatePreviewRotation() {
        guard let connection = preview.previewLayer.connection else { return }
        let angle: CGFloat
        switch view.window?.windowScene?.effectiveGeometry.interfaceOrientation {
        case .landscapeLeft: angle = 180
        case .landscapeRight: angle = 0
        case .portraitUpsideDown: angle = 270
        default: angle = 90
        }
        guard angle != connection.videoRotationAngle,
              connection.isVideoRotationAngleSupported(angle) else { return }
        expiry?.cancel()
        detections.removeAll()
        connection.videoRotationAngle = angle
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard isScanning else { return }

        let now = ContinuousClock.now
        let lifetime = Duration.milliseconds(400)
        var previous = detections.filter { $0.timestamp + lifetime > now }
        var current: [Detection] = []

        for case let code as AVMetadataMachineReadableCodeObject in metadataObjects {
            guard let payload = code.stringValue,
                  let bounds = preview.previewLayer.transformedMetadataObject(for: code)?.bounds else { continue }
            let visible = bounds.intersection(preview.bounds)
            guard !visible.isEmpty else { continue }

            let match = previous.firstIndex {
                $0.code.payload == payload && $0.code.bounds.intersects(visible)
            }
            let id = match.map { previous.remove(at: $0).code.id } ?? UUID()
            current.append(Detection(code: CameraCode(id: id, payload: payload, bounds: visible), timestamp: now))
        }

        detections = current + previous
        onCodes?(detections.map(\.code))
        expiry?.cancel()
        guard !detections.isEmpty else { return }
        // Metadata callbacks can stop entirely when the last code leaves the frame.
        expiry = Task { [weak self] in
            do {
                try await Task.sleep(for: lifetime)
                self?.detections.removeAll()
                self?.onCodes?([])
            } catch {}
        }
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private final class CameraSession: @unchecked Sendable {
    private static let codeTypes: [AVMetadataObject.ObjectType] = [
        .qr, .ean13, .ean8, .upce, .code128, .code39, .code93, .itf14, .codabar
    ]

    let session = AVCaptureSession()

    // Configure, start, and stop the capture session on the same queue.
    private let queue = DispatchQueue(label: "QRScan.camera")
    private var device: AVCaptureDevice?

    func update(
        running: Bool,
        torch: Bool,
        delegate: AVCaptureMetadataOutputObjectsDelegate,
        didStart: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        queue.async {
            guard running else {
                self.setTorch(false)
                if self.session.isRunning { self.session.stopRunning() }
                return
            }

            if self.device == nil {
                self.device = self.configure(delegate: delegate)
            }
            if self.device != nil, !self.session.isRunning {
                self.session.startRunning()
            }
            let started = self.session.isRunning
            if started { self.setTorch(torch) }
            DispatchQueue.main.async { didStart(started) }
        }
    }

    private func setTorch(_ enabled: Bool) {
        let mode: AVCaptureDevice.TorchMode = enabled ? .on : .off
        guard let device, device.hasTorch, device.isTorchModeSupported(mode),
              device.torchMode != mode, !enabled || device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.torchMode = mode
        } catch {
            // The capture device may be interrupted while changing the torch.
        }
    }

    private func configure(delegate: AVCaptureMetadataOutputObjectsDelegate) -> AVCaptureDevice? {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return nil }

        let output = AVCaptureMetadataOutput()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { return nil }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            return nil
        }

        session.addOutput(output)
        let availableTypes = output.availableMetadataObjectTypes
        let codeTypes = Self.codeTypes.filter { availableTypes.contains($0) }
        guard !codeTypes.isEmpty else {
            session.removeOutput(output)
            session.removeInput(input)
            return nil
        }
        output.setMetadataObjectsDelegate(delegate, queue: .main)
        output.metadataObjectTypes = codeTypes
        return device
    }
}
