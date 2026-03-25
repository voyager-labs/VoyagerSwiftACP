import ComposableArchitecture

struct TagSearchClient: Sendable {
    var search: @Sendable (_ request: TagSearchRequestPayload) async throws -> TagSearchResponsePayload
}

extension TagSearchClient: DependencyKey {
    static let liveValue: TagSearchClient = .init(
        search: { request in
            try await SearchXPCTransport.tagSearch(request)
        },
    )

    nonisolated(unsafe) static var testValue: TagSearchClient = .init(
        search: { request in .init(requestedTag: request.requestedTag, items: []) },
    )
}

extension TagSearchClient: TestDependencyKey {}

extension DependencyValues {
    nonisolated var tagSearchClient: TagSearchClient {
        get { self[TagSearchClient.self] }
        set { self[TagSearchClient.self] = newValue }
    }
}
