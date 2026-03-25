import ComposableArchitecture
import Foundation

struct SearchClient: Sendable {
    var search: @Sendable (_ request: SearchRequestPayload) async throws -> SearchResponsePayload
    var applyFilters: @Sendable (_ request: FiltersOnlyRequestPayload) async throws -> SearchResponsePayload
    var recentSearch: @Sendable (_ request: RecentSearchRequestPayload) async throws -> RecentSearchResponsePayload
    var tagSearch: @Sendable (_ request: TagSearchRequestPayload) async throws -> TagSearchResponsePayload
}

extension SearchClient: DependencyKey {
    static let liveValue: SearchClient = {
        SearchClient(
            search: { request in
                try await SearchXPCTransport.querySearch(request)
            },
            applyFilters: { request in
                try await SearchXPCTransport.applyFilters(request)
            },
            recentSearch: { request in
                try await SearchXPCTransport.recentSearch(request)
            },
            tagSearch: { request in
                try await SearchXPCTransport.tagSearch(request)
            },
        )
    }()

    nonisolated(unsafe) static var testValue: SearchClient = .init(
        search: { _ in .init(itemCount: 0, appliedFilters: nil, items: nil, error: nil) },
        applyFilters: { _ in .init(itemCount: 0, appliedFilters: nil, items: nil, error: nil) },
        recentSearch: { _ in .init(items: []) },
        tagSearch: { request in .init(requestedTag: request.requestedTag, items: []) },
    )
}

extension SearchClient: TestDependencyKey {}

extension DependencyValues {
    nonisolated var searchClient: SearchClient {
        get { self[SearchClient.self] }
        set { self[SearchClient.self] = newValue }
    }
}
