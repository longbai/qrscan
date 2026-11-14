import CoreGraphics
import Foundation

struct ScanResults: Identifiable {
    let id = UUID()
    let items: [ScanResult]
    let image: CGImage?

    init(_ payloads: [String]) {
        var seen = Set<String>()
        items = payloads.filter { seen.insert($0).inserted }.map { ScanResult($0) }
        image = nil
    }

    init(items: [ScanResult], image: CGImage? = nil) {
        self.items = items
        self.image = image
    }
}

enum ScanFormat: String {
    case qr = "QR"
    case ean13 = "EAN-13"
    case ean8 = "EAN-8"
    case upce = "UPC-E"
    case code128 = "Code 128"
    case code39 = "Code 39"
    case code93 = "Code 93"
    case itf14 = "ITF-14"
    case codabar = "Codabar"
}

struct ScanResult: Identifiable {
    let id = UUID()
    let raw: String
    let link: ScannedLink?
    let format: ScanFormat?
    // Photo bounds use a normalized coordinate space with the origin at the top left.
    let imageBounds: CGRect?

    init(_ raw: String, format: ScanFormat? = nil, imageBounds: CGRect? = nil) {
        self.raw = raw
        link = ScannedLink(raw)
        self.format = format
        self.imageBounds = imageBounds
    }
}

struct ScannedLink {
    struct Parameter: Identifiable {
        let id: Int
        let name: String
        let value: String?
        let encodedName: String
        let encodedValue: String?
    }

    let url: URL
    let scheme: String
    let host: String?
    let port: Int?
    let path: String
    let fragment: String?
    let parameters: [Parameter]

    init?(_ raw: String) {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.contains(where: \.isNewline),
              let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              let url = components.url else { return nil }

        switch scheme {
        case "http", "https":
            guard let host = components.host, !host.isEmpty else { return nil }
        case "mailto", "tel", "sms":
            guard !components.path.isEmpty else { return nil }
        default:
            guard let separator = candidate.firstIndex(of: ":"),
                  candidate[candidate.index(after: separator)...].hasPrefix("//"),
                  components.host?.isEmpty == false else { return nil }
        }

        self.url = url
        self.scheme = scheme
        host = components.host
        port = components.port
        path = components.path
        fragment = components.fragment
        // Read the source query directly so Foundation normalization cannot change the bytes shown.
        let beforeFragment = candidate.prefix { $0 != "#" }
        guard let question = beforeFragment.firstIndex(of: "?"),
              beforeFragment.index(after: question) != beforeFragment.endIndex else {
            parameters = []
            return
        }
        let query = beforeFragment[beforeFragment.index(after: question)...]
        parameters = query.split(separator: "&", omittingEmptySubsequences: false).enumerated().map { index, field in
            let equals = field.firstIndex(of: "=")
            let name = String(field.prefix { $0 != "=" })
            let value = equals.map { String(field[field.index(after: $0)...]) }
            return Parameter(
                id: index, name: name.removingPercentEncoding ?? name,
                value: value.map { $0.removingPercentEncoding ?? $0 },
                encodedName: name, encodedValue: value
            )
        }
    }
}
