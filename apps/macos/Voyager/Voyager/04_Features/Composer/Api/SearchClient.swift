import ComposableArchitecture
import Foundation
import SwiftDotenv

struct SearchClient: Sendable {
    var search: @Sendable (_ request: SearchRequestPayload) async throws -> SearchResponsePayload
    var applyFilters: @Sendable (_ request: FiltersOnlyRequestPayload) async throws -> SearchResponsePayload
}

extension SearchClient: DependencyKey {
    static let liveValue: SearchClient = {
        @Sendable
        func post<U: Decodable>(path: String, body: some Encodable) async throws -> U {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            let baseURL = await MainActor.run { Dotenv.publicBackendURL }
            let appVersion = await MainActor.run { AppVersionInfo.shortVersion }
            let deviceId = await MainActor.run { DeviceIdentifierProvider.current() }
            let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            let url = baseURL.appendingPathComponent(path)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let deviceId {
                request.setValue(deviceId, forHTTPHeaderField: "X-Voyager-Device-Id")
            }
            request.setValue(appVersion, forHTTPHeaderField: "X-Voyager-App-Version")
            request.setValue(osVersion, forHTTPHeaderField: "X-Voyager-OS-Version")
            request.httpBody = try encoder.encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200 ..< 300 ~= http.statusCode else {
                throw URLError(.badServerResponse)
            }
            return try decoder.decode(U.self, from: data)
        }

        return SearchClient(
            search: { request in
                try await post(path: "api/collection", body: request)
            },
            applyFilters: { request in
                try await post(path: "api/collection/filters", body: request)
            },
        )
    }()

    nonisolated(unsafe) static var testValue: SearchClient = .init(
        search: { _ in .init(itemCount: 0, appliedFilters: nil, items: nil) },
        applyFilters: { _ in .init(itemCount: 0, appliedFilters: nil, items: nil) },
    )
}

extension SearchClient: TestDependencyKey {}

extension DependencyValues {
    nonisolated var searchClient: SearchClient {
        get { self[SearchClient.self] }
        set { self[SearchClient.self] = newValue }
    }
}
