import Foundation
import ImageIO
import Vision

enum PhotoScanner {
    private static let codeTypes: [VNBarcodeSymbology] = [
        .qr, .ean13, .ean8, .upce, .code128, .code39, .code93, .itf14, .codabar
    ]

    enum Failure: LocalizedError {
        case unreadableImage

        var errorDescription: String? {
            String(localized: "Couldn’t read this image. Choose another image.")
        }
    }

    static func scan(_ data: Data) async throws -> [String] {
        let worker = Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) > 0 else {
                throw Failure.unreadableImage
            }

            let index = CGImageSourceGetPrimaryImageIndex(source)
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let rawOrientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
            let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                throw Failure.unreadableImage
            }

            let request = VNDetectBarcodesRequest()
            let supportedTypes = try request.supportedSymbologies()
            request.symbologies = codeTypes.filter { supportedTypes.contains($0) }
            try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
            try Task.checkCancellation()

            let observations = (request.results ?? []).sorted {
                if $0.boundingBox.midY == $1.boundingBox.midY {
                    return $0.boundingBox.midX < $1.boundingBox.midX
                }
                return $0.boundingBox.midY > $1.boundingBox.midY
            }
            return observations.compactMap(\.payloadStringValue)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
