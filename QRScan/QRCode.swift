import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import UniformTypeIdentifiers

enum QRCode {
    enum GenerationError: Error {
        case tooLong, unavailable
    }

    enum CorrectionLevel: String, CaseIterable, Identifiable {
        case low = "L"
        case medium = "M"
        case quartile = "Q"
        case high = "H"

        var id: Self { self }

        var maximumByteCount: Int {
            switch self {
            case .low: 2953
            case .medium: 2331
            case .quartile: 1663
            case .high: 1273
            }
        }
    }

    enum ImageFormat: String, CaseIterable, Identifiable {
        case png = "PNG"
        case jpeg = "JPEG"

        var id: Self { self }
        var type: UTType { self == .png ? .png : .jpeg }
        var fileExtension: String { self == .png ? "png" : "jpg" }

        func encode(_ image: CGImage) -> Data? {
            let image = UIImage(cgImage: image)
            switch self {
            case .png: return image.pngData()
            case .jpeg: return image.jpegData(compressionQuality: 0.95)
            }
        }
    }

    private static let context = CIContext()

    static func generate(
        _ text: String,
        correctionLevel: CorrectionLevel = .medium,
        foreground: UIColor = .black,
        background: UIColor = .white
    ) -> Result<CGImage, GenerationError> {
        guard !text.isEmpty else { return .failure(.unavailable) }
        guard text.utf8.count <= correctionLevel.maximumByteCount else { return .failure(.tooLong) }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = correctionLevel.rawValue
        guard let code = filter.outputImage, !code.extent.isEmpty else { return .failure(.unavailable) }

        let backgroundColor = CIColor(color: background)
        let palette = CIFilter.falseColor()
        palette.inputImage = code
        palette.color0 = CIColor(color: foreground)
        palette.color1 = backgroundColor
        guard let colored = palette.outputImage else { return .failure(.unavailable) }

        // QR readers need a quiet zone of at least four modules.
        let bounds = code.extent.insetBy(dx: -4, dy: -4)
        let canvas = CIImage(color: backgroundColor).cropped(to: bounds)
        let image = colored.composited(over: canvas).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let rendered = context.createCGImage(image, from: image.extent) else { return .failure(.unavailable) }
        return .success(rendered)
    }
}
