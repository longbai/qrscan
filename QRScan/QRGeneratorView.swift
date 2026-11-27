import CoreTransferable
import Photos
import SwiftUI

struct ClipboardPasteButton: View {
    private struct Payload: Transferable {
        let text: String

        static var transferRepresentation: some TransferRepresentation {
            ProxyRepresentation(importing: { (text: String) in Payload(text: text) })
            ProxyRepresentation(importing: { (url: URL) in Payload(text: url.absoluteString) })
        }
    }

    let onPaste: (String) -> Void

    var body: some View {
        PasteButton(payloadType: Payload.self) { items in
            if let text = items.first(where: { !$0.text.isEmpty })?.text {
                onPaste(text)
            }
        }
        .tint(.scanMint)
        .buttonBorderShape(.capsule)
        .frame(minHeight: 44)
    }
}

struct QRGeneratorView: View {
    private enum SaveNotice: String, Identifiable {
        case saved, denied, failed
        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @FocusState private var isEditing: Bool
    @State private var primary: String
    @State private var correctionLevel = QRCode.CorrectionLevel.medium
    @State private var foreground = Color.black
    @State private var background = Color.white
    @State private var format = QRCode.ImageFormat.png
    @State private var result: Result<CGImage, QRCode.GenerationError>?
    @State private var isSaving = false
    @State private var saveNotice: SaveNotice?
    private let initialText: String

    init(initialText: String) {
        self.initialText = initialText
        _primary = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        contentForm
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Error Correction").font(.headline).accessibilityHidden(true)
                                Picker("Error Correction", selection: $correctionLevel) {
                                    ForEach(QRCode.CorrectionLevel.allCases) { level in
                                        Text(verbatim: level.rawValue).tag(level)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: correctionLevel) {
                                    if result != nil { refreshPreview() }
                                }
                            }
                            Button(action: generate) {
                                Text("Generate QR Code")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.scanMint)
                            .foregroundStyle(Color.scanInk)
                            .disabled(primary.isEmpty)
                            resultSection
                        }
                        .id("qr-preview")
                    }
                    .frame(maxWidth: 520)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: result != nil) { _, hasResult in
                    if hasResult { scroll.scrollTo("qr-preview", anchor: .top) }
                }
                .background(Color.scanInk)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Generate QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(.scanMint)
                }
            }
        }
        .alert(item: $saveNotice) { notice in
            switch notice {
            case .saved:
                Alert(title: Text("Saved to Photos"), dismissButton: .default(Text("OK")))
            case .denied:
                Alert(title: Text("Photos Access Is Off"),
                      message: Text("Allow QRScan to add photos in Settings."),
                      primaryButton: .default(Text("Open Settings")) {
                          if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                      },
                      secondaryButton: .cancel())
            case .failed:
                Alert(title: Text("Could not save the QR code."), dismissButton: .default(Text("OK")))
            }
        }
        .task {
            if !initialText.isEmpty, primary == initialText, result == nil { generate() }
        }
    }

    private var contentForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Text or Link").font(.headline)
                Spacer()
                ClipboardPasteButton(onPaste: updatePrimary)
            }
            TextEditor(text: $primary)
                .focused($isEditing)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(height: 96)
                .padding(10)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("Text or Link")
                .onChange(of: primary) { result = nil }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let result {
            ColorPicker("Foreground Color", selection: $foreground, supportsOpacity: false)
                .onChange(of: foreground) { refreshPreview() }
            ColorPicker("Background Color", selection: $background, supportsOpacity: false)
                .onChange(of: background) { refreshPreview() }
            switch result {
            case .success(let code):
                Image(code, scale: 1, label: Text("Generated QR Code"))
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: 280)
                    .frame(maxWidth: .infinity)
                Picker("Image Format", selection: $format) {
                    ForEach(QRCode.ImageFormat.allCases) { option in
                        Text(verbatim: option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Button {
                    Task { [format] in await save(code, format: format) }
                } label: {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isSaving)
                if isSaving { ProgressView("Saving…") }
            case .failure(let error):
                switch error {
                case .tooLong:
                    Text("This text is too long for the selected correction level.")
                case .unavailable:
                    Text("Could not generate the QR code.")
                }
            }
        }
    }

    private func updatePrimary(_ text: String) {
        guard !primary.utf8.elementsEqual(text.utf8) else { return }
        primary = text
        result = nil
    }

    private func generate() {
        isEditing = false
        refreshPreview()
    }

    private func refreshPreview() {
        result = QRCode.generate(
            primary,
            correctionLevel: correctionLevel,
            foreground: UIColor(foreground),
            background: UIColor(background)
        )
    }

    @MainActor
    private func save(_ image: CGImage, format: QRCode.ImageFormat) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveNotice = .denied
            return
        }
        guard let data = format.encode(image) else {
            saveNotice = .failed
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "QRScan.\(format.fileExtension)"
                options.uniformTypeIdentifier = format.type.identifier
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: options)
            }
            saveNotice = .saved
        } catch {
            saveNotice = .failed
        }
    }
}
