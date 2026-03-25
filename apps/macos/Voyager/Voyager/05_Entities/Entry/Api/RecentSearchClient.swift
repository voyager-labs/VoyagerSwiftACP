import ComposableArchitecture

struct RecentSearchClient: Sendable {
    var search: @Sendable (_ request: RecentSearchRequestPayload) async throws -> RecentSearchResponsePayload
}

extension RecentSearchClient: DependencyKey {
    static let liveValue: RecentSearchClient = .init(
        search: { request in
            try await SearchXPCTransport.recentSearch(request)
        },
    )

    nonisolated(unsafe) static var testValue: RecentSearchClient = .init(
        search: { _ in .init(items: []) },
    )
}

extension RecentSearchClient: TestDependencyKey {}

extension DependencyValues {
    nonisolated var recentSearchClient: RecentSearchClient {
        get { self[RecentSearchClient.self] }
        set { self[RecentSearchClient.self] = newValue }
    }
}
