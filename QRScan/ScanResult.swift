import Foundation

struct ScanResults: Identifiable {
    let id = UUID()
    let items: [ScanResult]

    init(_ payloads: [String]) {
        var seen = Set<String>()
        items = payloads.filter { seen.insert($0).inserted }.map(ScanResult.init)
    }
}

struct ScanResult: Identifiable {
    let id = UUID()
    let raw: String
    let link: ScannedLink?

    init(_ raw: String) {
        self.raw = raw
        link = ScannedLink(raw)
    }
}

struct ScannedLink {
    struct Parameter: Identifiable {
        let id: Int
        let name: String
        let value: String?
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
        parameters = (components.queryItems ?? []).enumerated().map { index, item in
            Parameter(id: index, name: item.name, value: item.value)
        }
    }
}
