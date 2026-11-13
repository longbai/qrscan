import XCTest
@testable import QRScan

final class ScanResultTests: XCTestCase {
    func testLinkKeepsRawPayloadAndDecodesDisplayComponents() throws {
        let payload = "https://example.com:8443/a%20b?tag=%E4%B8%AD%E6%96%87#part%202"
        let result = ScanResult(payload)
        let link = try XCTUnwrap(result.link)

        XCTAssertEqual(result.raw, payload)
        XCTAssertEqual(link.url.absoluteString, payload)
        XCTAssertEqual(link.scheme, "https")
        XCTAssertEqual(link.host, "example.com")
        XCTAssertEqual(link.port, 8443)
        XCTAssertEqual(link.path, "/a b")
        XCTAssertEqual(link.fragment, "part 2")
        XCTAssertEqual(link.parameters.first?.value, "中文")
    }

    func testRepeatedParametersKeepTheirOrderAndDistinctValues() throws {
        let link = try XCTUnwrap(ScanResult("https://example.com/?tag=first&tag=a%2Bb&tag=a+b").link)

        XCTAssertEqual(link.parameters.map(\.id), [0, 1, 2])
        XCTAssertEqual(link.parameters.map(\.name), ["tag", "tag", "tag"])
        XCTAssertEqual(link.parameters.map(\.value), ["first", "a+b", "a+b"])
    }

    func testEmptyAndMissingParameterValuesAreDistinct() throws {
        let link = try XCTUnwrap(ScanResult("https://example.com/?empty=&flag&=value").link)

        XCTAssertEqual(link.parameters.map(\.name), ["empty", "flag", ""])
        XCTAssertEqual(link.parameters.map(\.value), ["", nil, "value"])
    }

    func testBarcodeAndPlainTextRemainCopyableAsRawContent() {
        for payload in ["0012345678905", "Hello", "WIFI:T:WPA;S:Guest;P:password;;", "https:///missing-host"] {
            let result = ScanResult(payload)
            XCTAssertEqual(result.raw, payload)
            XCTAssertNil(result.link)
        }
    }

    func testRecognizesMailAndAppLinks() {
        XCTAssertEqual(ScanResult("mailto:hello@example.com?subject=Hi").link?.parameters.first?.value, "Hi")
        XCTAssertEqual(ScanResult("myapp://route?item=1").link?.host, "route")
    }

    func testMultipleCodesDeduplicateInFirstSeenOrder() {
        let results = ScanResults(["0012345678905", "https://example.com", "0012345678905", "Hello"])
        XCTAssertEqual(results.items.map(\.raw), ["0012345678905", "https://example.com", "Hello"])
    }

    func testAppResourcesIncludeEnglishAndSimplifiedChinese() throws {
        let app = Bundle.main
        XCTAssertEqual(app.developmentLocalization, "en")
        XCTAssertTrue(app.localizations.contains("en"))
        XCTAssertTrue(app.localizations.contains("zh-Hans"))
        let folder = try XCTUnwrap(app.path(forResource: "zh-Hans", ofType: "lproj"))
        let chinese = try XCTUnwrap(Bundle(path: folder))
        XCTAssertEqual(chinese.localizedString(forKey: "Scan Result", value: nil, table: nil), "扫描结果")
        XCTAssertEqual(chinese.localizedString(forKey: "CFBundleDisplayName", value: nil, table: "InfoPlist"), "扫码")
    }
}
