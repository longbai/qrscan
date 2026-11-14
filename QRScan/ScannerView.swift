import AVFoundation
import PhotosUI
import SwiftUI

struct ScannerView: View {
    private enum CameraAccess {
        case checking, ready, denied, unavailable
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var cameraAccess = CameraAccess.checking
    @State private var hasTorch = false
    @State private var isTorchOn = false
    @State private var photo: PhotosPickerItem?
    @State private var isPickingPhoto = false
    @State private var focus: CGRect?
    @State private var cameraTransition: Task<Void, Never>?
    @State private var cameraCodes: [CameraCode] = []
    @State private var results: ScanResults?
    @State private var photoError: String?

    private var shouldRunCamera: Bool {
        scenePhase == .active && results == nil
            && (focus == nil || cameraTransition != nil)
            && !isPickingPhoto && photo == nil && photoError == nil
    }

    private var singleCodeID: UUID? {
        guard shouldRunCamera, focus == nil, cameraCodes.count == 1 else { return nil }
        return cameraCodes.first?.id
    }

    var body: some View {
        let compactHeight = verticalSizeClass == .compact
        return VStack(spacing: compactHeight ? 8 : 20) {
            header
            cameraViewport
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(.horizontal, 20)
        .padding(.top, compactHeight ? 4 : 16)
        .padding(.bottom, compactHeight ? 4 : 12)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.13, blue: 0.11), Color(red: 0.02, green: 0.06, blue: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .task(id: scenePhase) {
            if scenePhase == .active { await checkCamera() }
        }
        .task(id: photo) {
            if let photo { await readPhoto(photo) }
        }
        .photosPicker(isPresented: $isPickingPhoto, selection: $photo, matching: .images)
        .sheet(item: $results, onDismiss: resetCameraFocus) { results in
            ScanResultsView(results: results)
        }
        .onChange(of: shouldRunCamera) { _, running in
            if !running { cameraCodes = [] }
        }
        .alert("Image Scan", isPresented: Binding(
            get: { photoError != nil },
            set: { if !$0 { photoError = nil } }
        )) {
            Button("OK", role: .cancel) { photoError = nil }
        } message: {
            Text(verbatim: photoError ?? "")
        }
        .onDisappear(perform: resetCameraFocus)
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Color.scanMint)
                .frame(width: 48, height: 48)
                .background(Color.scanMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Code Scanner")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Scan QR codes and barcodes")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var cameraViewport: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let side = min(size.width * 0.67, size.height * 0.64, 280)
            let guide = CGRect(
                x: (size.width - side) / 2,
                y: (size.height - side) / 2,
                width: side,
                height: side
            )

            ZStack {
                Color.scanInk
                if cameraAccess == .ready {
                    CameraPreview(isScanning: shouldRunCamera, isTorchOn: isTorchOn) { codes in
                        if shouldRunCamera, focus == nil { cameraCodes = codes }
                    } onUnavailable: {
                        cameraAccess = .unavailable
                        cameraCodes = []
                    }
                    .accessibilityHidden(true)
                    scannerOverlay(guide: guide, size: size)
                    if shouldRunCamera, focus == nil, cameraCodes.count > 1 {
                        ForEach(cameraCodes) { code in
                            codeMarker(code, viewport: size)
                        }
                    }
                } else {
                    cameraPlaceholder
                        .padding(20)
                }
            }
            .task(id: singleCodeID) {
                guard let id = singleCodeID else { return }
                do {
                    try await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled, singleCodeID == id, let code = cameraCodes.first else { return }
                    selectCode(code, viewport: size)
                } catch {}
            }
            .onChange(of: size) { _, _ in
                // Detection bounds belong to the previous viewfinder size.
                resetCameraFocus()
            }
            .overlay(alignment: .topTrailing) {
                if cameraAccess == .ready, hasTorch {
                    torchButton.padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(.white.opacity(0.14))
                    .allowsHitTesting(false)
            }
        }
    }

    private var torchButton: some View {
        let label: LocalizedStringKey = isTorchOn ? "Turn off flashlight" : "Turn on flashlight"
        return Button {
            isTorchOn.toggle()
        } label: {
            Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                .foregroundStyle(isTorchOn ? Color.scanInk : .white)
                .frame(width: 48, height: 48)
                .background(isTorchOn ? Color.scanMint : .black.opacity(0.62), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private func scannerOverlay(guide: CGRect, size: CGSize) -> some View {
        let frame = focus ?? guide

        return ZStack {
            Color.black.opacity(0.49)
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()

            ScanCorners()
                .stroke(
                    focus == nil ? .white : Color.scanMint,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            if focus == nil, size.height >= 185 {
                Text("Align a QR code or barcode in the frame")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.62), in: Capsule())
                    .position(x: size.width / 2, y: min(guide.maxY + 30, size.height - 20))
            }
        }
        .opacity(focus != nil || cameraCodes.count < 2 ? 1 : 0)
        .allowsHitTesting(false)
    }

    private var cameraPlaceholder: some View {
        VStack(spacing: 13) {
            switch cameraAccess {
            case .checking:
                ProgressView("Starting camera")
                    .tint(.scanMint)
            case .denied, .unavailable:
                Image(systemName: "camera.fill")
                    .font(.title)
                    .foregroundStyle(Color.scanMint)
                    .accessibilityHidden(true)
                Text((cameraAccess == .denied ? "Camera Access Is Off" : "Camera Unavailable") as LocalizedStringKey)
                    .font(.headline)
                Text((cameraAccess == .denied ? "Enable camera access in Settings or scan a photo." : "Choose a photo with a QR code or barcode.") as LocalizedStringKey)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if cameraAccess == .denied, let settings = URL(string: UIApplication.openSettingsURLString) {
                    Button("Open Settings") { openURL(settings) }
                        .buttonStyle(.bordered)
                        .tint(.scanMint)
                }
            case .ready:
                EmptyView()
            }
        }
    }

    private var footer: some View {
        Button {
            isPickingPhoto = true
        } label: {
            HStack(spacing: 10) {
                if photo != nil {
                    ProgressView().tint(.scanInk)
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.body.weight(.semibold))
                }
                Text((photo != nil ? "Scanning image…" : "Choose Photo") as LocalizedStringKey)
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.scanInk)
        .background(Color.scanMint, in: RoundedRectangle(cornerRadius: 18))
        .disabled(photo != nil || focus != nil)
    }

    @MainActor
    private func checkCamera() async {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            cameraAccess = .unavailable
            return
        }
        hasTorch = device.hasTorch

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            if cameraAccess != .unavailable { cameraAccess = .ready }
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraAccess = granted ? .ready : .denied
        case .denied:
            cameraAccess = .denied
        case .restricted:
            cameraAccess = .unavailable
        @unknown default:
            cameraAccess = .unavailable
        }
    }

    private func codeMarker(_ code: CameraCode, viewport: CGSize) -> some View {
        let bounds = code.bounds
        let x = min(max(bounds.midX, 24), viewport.width - 24)
        let y = bounds.maxY + 48 <= viewport.height ? bounds.maxY + 24 : max(bounds.minY - 24, 24)

        return ZStack {
            ScanCorners()
                .stroke(Color.scanMint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: bounds.width + 8, height: bounds.height + 8)
                .position(x: bounds.midX, y: bounds.midY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            Button {
                selectCode(code, viewport: viewport)
            } label: {
                Image(systemName: "arrow.right")
                    .font(.headline)
                    .foregroundStyle(Color.scanInk)
                    .frame(width: 36, height: 36)
                    .background(Color.scanMint, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View scan result")
            .accessibilityValue(String(code.payload.prefix(100)))
            .position(x: x, y: y)
        }
    }

    private func selectCode(_ code: CameraCode, viewport: CGSize) {
        guard shouldRunCamera, focus == nil else { return }
        let viewportBounds = CGRect(origin: .zero, size: viewport)
        withAnimation(reduceMotion ? nil : .spring(response: 0.29, dampingFraction: 0.83)) {
            focus = code.bounds.insetBy(dx: -11, dy: -11).intersection(viewportBounds)
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        cameraTransition = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(reduceMotion ? 80 : 340))
                results = ScanResults([code.payload])
                cameraTransition = nil
            } catch {
                return
            }
        }
    }

    private func resetCameraFocus() {
        cameraTransition?.cancel()
        cameraTransition = nil
        cameraCodes = []
        focus = nil
    }

    @MainActor
    private func readPhoto(_ item: PhotosPickerItem) async {
        defer {
            if photo == item { photo = nil }
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw PhotoScanner.Failure.unreadableImage
            }
            let payloads = try await PhotoScanner.scan(data)
            guard !Task.isCancelled, photo == item else { return }
            if payloads.isEmpty {
                photoError = String(localized: "No QR code or barcode found in this image.")
            } else {
                results = ScanResults(payloads)
            }
        } catch {
            guard !Task.isCancelled, photo == item else { return }
            photoError = (error as? PhotoScanner.Failure)?.errorDescription
                ?? String(localized: "Couldn’t scan this image. Try again or choose another image.")
        }
    }
}

private struct ScanCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(27, min(rect.width, rect.height) / 3)
        let radius = min(11, length * 0.65)
        var path = Path()
        for (x, dx) in [(rect.minX, CGFloat(1)), (rect.maxX, CGFloat(-1))] {
            for (y, dy) in [(rect.minY, CGFloat(1)), (rect.maxY, CGFloat(-1))] {
                path.move(to: CGPoint(x: x, y: y + dy * length))
                path.addLine(to: CGPoint(x: x, y: y + dy * radius))
                path.addQuadCurve(
                    to: CGPoint(x: x + dx * radius, y: y),
                    control: CGPoint(x: x, y: y)
                )
                path.addLine(to: CGPoint(x: x + dx * length, y: y))
            }
        }
        return path
    }
}
