import ComposableArchitecture
import Foundation

/// MDItem 프로퍼티 레지스트리(`/api/mditem/properties`)를 조회하는 클라이언트.
struct MDItemPropertyClient: Sendable {
    var fetchAll: @Sendable () async throws -> [MDItemProperty]
}

struct BackendURLProvider: Sendable {
    var fetchBaseURL: @Sendable () throws -> URL
}

private struct Envelope: Decodable {
    let data: DataPayload
}

private struct DataPayload: Decodable {
    let items: [MDItemProperty]
}

extension MDItemPropertyClient: DependencyKey, TestDependencyKey {
    static let liveValue = MDItemPropertyClient(
        fetchAll: {
            @Dependency(\.backendURLProvider)
            var backendURLProvider

            let baseURL = try backendURLProvider.fetchBaseURL()
            let url = baseURL.appendingPathComponent("/api/mditem/properties")

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  200 ..< 300 ~= http.statusCode
            else {
                throw URLError(.badServerResponse)
            }

            let decoded: Envelope = try await MainActor.run {
                try JSONDecoder().decode(Envelope.self, from: data)
            }
            return decoded.data.items
        },
    )

    nonisolated(unsafe) static var testValue: MDItemPropertyClient = .init(fetchAll: { [] })
}

extension DependencyValues {
    nonisolated var mdItemPropertyClient: MDItemPropertyClient {
        get { self[MDItemPropertyClient.self] }
        set { self[MDItemPropertyClient.self] = newValue }
    }

    nonisolated var backendURLProvider: BackendURLProvider {
        get { self[BackendURLProvider.self] }
        set { self[BackendURLProvider.self] = newValue }
    }
}

extension BackendURLProvider: DependencyKey {
    static let liveValue = BackendURLProvider {
        try resolveBackendBaseURL()
    }
}

extension BackendURLProvider: TestDependencyKey {
    nonisolated(unsafe) static var testValue: BackendURLProvider = .init {
        throw URLError(.badURL)
    }
}

private nonisolated func resolveBackendBaseURL() throws -> URL {
    let env = ProcessInfo.processInfo.environment

    if let envURL = env["BACKEND_URL"],
       !envURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       let url = URL(string: envURL)
    {
        return url
    }

    let host = env["PUBLIC_VOYAGER_HOST"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    let port = env["PUBLIC_VOYAGER_PORT"]?.trimmingCharacters(in: .whitespacesAndNewlines)

    let resolvedHost = host.flatMap { $0.isEmpty ? nil : $0 } ?? "localhost"
    let resolvedPort = port.flatMap { $0.isEmpty ? nil : $0 } ?? "8000"

    let base = "http://\(resolvedHost):\(resolvedPort)"
    guard let url = URL(string: base) else {
        throw URLError(.badURL, userInfo: [
            NSLocalizedDescriptionKey: "Invalid backend base URL: \(base)",
        ])
    }
    return url
}
