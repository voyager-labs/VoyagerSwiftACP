import Foundation

struct GatewayEnvironment: Equatable {
    let baseURL: URL?
    let binding: String

    init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.percentEncodedQuery == nil,
              components.percentEncodedFragment == nil
        else {
            baseURL = nil
            binding = ""
            return
        }

        components.scheme = scheme
        components.host = host
        if (scheme == "http" && components.port == 80) || (scheme == "https" && components.port == 443) {
            components.port = nil
        }
        components.percentEncodedPath = Self.canonicalPath(components.percentEncodedPath)

        guard let baseURL = components.url else {
            baseURL = nil
            binding = ""
            return
        }

        self.baseURL = baseURL
        binding = baseURL.absoluteString
    }

    private static func canonicalPath(_ path: String) -> String {
        var segments: [String] = []
        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch segment {
            case ".":
                continue
            case "..":
                if !segments.isEmpty {
                    segments.removeLast()
                }
            default:
                segments.append(String(segment))
            }
        }

        guard !segments.isEmpty else { return "/" }
        return "/" + segments.joined(separator: "/")
    }
}
