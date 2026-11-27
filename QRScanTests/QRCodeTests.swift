import CoreImage
import ImageIO
import UIKit
import XCTest
@testable import QRScan

final class QRCodeTests: XCTestCase {
    func testGeneratedCodesPreserveLinksAndMultilingualText() throws {
        let detector = try XCTUnwrap(CIDetector(
            ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ))
        for payload in ["https://example.com/?tag=a+b&other=a%2Bb", " 简体中文・日本語😀\nSecond line "] {
            let image = try QRCode.generate(payload).get()
            let features = detector.features(in: CIImage(cgImage: image))
            let messages = features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }

            XCTAssertEqual(messages, [payload])
        }
    }

    func testRejectsOversizeUTF8Payload() {
        let text = String(repeating: "日", count: 778)
        guard case .failure(.tooLong) = QRCode.generate(text) else {
            return XCTFail("A 2,334-byte input should exceed the byte limit")
        }
    }

    func testEncodesSelectedCorrectionLevel() throws {
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil))
        for level in QRCode.CorrectionLevel.allCases {
            let image = try QRCode.generate("QRScan", correctionLevel: level).get()
            let features = detector.features(in: CIImage(cgImage: image))
            let feature = try XCTUnwrap(features.first as? CIQRCodeFeature)
            let descriptor = try XCTUnwrap(feature.symbolDescriptor)
            XCTAssertEqual(descriptor.errorCorrectionLevel.rawValue, Int(try XCTUnwrap(level.rawValue.utf8.first)))
        }

        let text = String(repeating: "x", count: 1274)
        XCTAssertNoThrow(try QRCode.generate(text).get())
        guard case .failure(.tooLong) = QRCode.generate(text, correctionLevel: .high) else {
            return XCTFail("Level H should reject a 1,274-byte payload")
        }
    }

    func testColoredExportsKeepTheirFormatAndRemainScannable() throws {
        let payload = "https://example.com/色?tag=a%2Bb"
        let color = UIColor(red: 0.14, green: 0.25, blue: 0.46, alpha: 1)
        let image = try QRCode.generate(payload, foreground: color, background: .yellow).get()
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var corner = [UInt8](repeating: 0, count: 4)
        CIContext().render(CIImage(cgImage: image), toBitmap: &corner, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: colorSpace)
        XCTAssertEqual(corner, [255, 255, 0, 255])
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil))
        for format in QRCode.ImageFormat.allCases {
            let data = try XCTUnwrap(format.encode(image))
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let type = try XCTUnwrap(CGImageSourceGetType(source))
            XCTAssertEqual(type as String, format.type.identifier)
            let exported = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let features = detector.features(in: CIImage(cgImage: exported))
            XCTAssertEqual(features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }, [payload])
        }
        XCTAssertNoThrow(try QRCode.generate(payload, foreground: .white, background: .white).get())
    }
}
