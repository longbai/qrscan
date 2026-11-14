import Foundation
import ImageIO
import Vision

enum PhotoScanner {
    private static let codeTypes: [VNBarcodeSymbology: ScanFormat] = [
        .qr: .qr, .ean13: .ean13, .ean8: .ean8, .upce: .upce, .code128: .code128,
        .code39: .code39, .code93: .code93, .itf14: .itf14, .codabar: .codabar
    ]

    enum Failure: LocalizedError {
        case unreadableImage

        var errorDescription: String? {
            String(localized: "Couldn’t read this image. Choose another image.")
        }
    }

    static func scan(_ data: Data) async throws -> ScanResults {
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
            request.symbologies = codeTypes.keys.filter { supportedTypes.contains($0) }
            try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
            try Task.checkCancellation()

            let observations = (request.results ?? []).sorted {
                if $0.boundingBox.midY == $1.boundingBox.midY {
                    return $0.boundingBox.midX < $1.boundingBox.midX
                }
                return $0.boundingBox.midY > $1.boundingBox.midY
            }
            let items = observations.compactMap { observation -> ScanResult? in
                guard let payload = observation.payloadStringValue else { return nil }
                let bounds = observation.boundingBox
                return ScanResult(
                    payload, format: codeTypes[observation.symbology],
                    imageBounds: CGRect(x: bounds.minX, y: 1 - bounds.maxY,
                                        width: bounds.width, height: bounds.height)
                )
            }
            let thumbnail: CGImage?
            if items.count > 1 {
                thumbnail = CGImageSourceCreateThumbnailAtIndex(source, index, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 720
                ] as CFDictionary)
            } else {
                thumbnail = nil
            }
            return ScanResults(items: items, image: thumbnail)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
