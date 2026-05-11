import ComposableArchitecture
import Foundation
import VoyagerShared

public struct SearchClient: Sendable {
    public var search: @Sendable (_ request: VoyagerShared.SearchRequestPayload) async throws -> VoyagerShared
        .SearchResponsePayload
    public var applyFilters: @Sendable (_ request: VoyagerShared.FiltersOnlyRequestPayload) async throws -> VoyagerShared
        .SearchResponsePayload
}

public extension SearchClient: DependencyKey {
    static let liveValue: SearchClient = .init(
        search: { request in
            try await SearchXPCTransport.querySearch(request)
        },
        applyFilters: { request in
            try await SearchXPCTransport.applyFilters(request)
        }
    )

    nonisolated(unsafe) static var testValue: SearchClient = .init(
        search: { _ in .init(itemCount: 0, appliedFilters: nil, items: nil, error: nil) },
        applyFilters: { _ in .init(itemCount: 0, appliedFilters: nil, items: nil, error: nil) }
    )
}

extension SearchClient: TestDependencyKey {}

public extension DependencyValues {
    nonisolated var searchClient: SearchClient {
        get { self[SearchClient.self] }
        set { self[SearchClient.self] = newValue }
    }
}
