import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ScanActionViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let provider = items.flatMap { $0.attachments ?? [] }
            .first { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        let host = UIHostingController(rootView: ScanActionView(provider: provider) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
}

private struct ScanActionView: View {
    let provider: NSItemProvider?
    let finish: () -> Void

    @State private var results: ScanResults?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let results {
                ScanResultsView(results: results, allowsOpeningLinks: false, onFinish: finish)
            } else {
                NavigationStack {
                    Group {
                        if let errorMessage {
                            Text(verbatim: errorMessage)
                                .multilineTextAlignment(.center)
                        } else {
                            ProgressView("Scanning image…")
                        }
                    }
                    .padding(20)
                    .navigationTitle("Image Scan")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done", action: finish)
                        }
                    }
                }
                .tint(.scanMint)
            }
        }
        .preferredColorScheme(.dark)
        .task { await scan() }
    }

    @MainActor
    private func scan() async {
        do {
            guard let provider else { throw PhotoScanner.Failure.unreadableImage }
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    if let data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: error ?? PhotoScanner.Failure.unreadableImage)
                    }
                }
            }
            try Task.checkCancellation()
            let scan = try await PhotoScanner.scan(data)
            try Task.checkCancellation()
            if scan.items.isEmpty {
                errorMessage = String(localized: "No QR code or barcode found in this image.")
            } else {
                results = scan
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = String(localized: "Couldn’t scan this image. Try again or choose another image.")
        }
    }
}
