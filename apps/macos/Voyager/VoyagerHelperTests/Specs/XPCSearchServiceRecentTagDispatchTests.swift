import Foundation
import Logging
@testable import VoyagerHelper
import VoyagerShared
import XCTest

@MainActor
final class XPCSearchServiceRecentTagDispatchTests: XCTestCase {
    func testRecentDispatchDecodesRequestCallsServiceAndEncodesReply() async throws {
        let expected = RecentSearchResponsePayload(items: [makeEntry(fullPath: "/tmp/recent.txt")])
        let service = StubSearchExecutionService(
            onRecent: { request in
                XCTAssertEqual(request.scopeMode, .allIndexed)
                XCTAssertEqual(request.resultCap, 100)
                return expected
            },
            onTag: { _ in .init(requestedTag: "", items: []) },
        )
        let sut = XPCSearchService(service: service, logger: .init(label: "test"))

        let requestData = try JSONEncoder().encode(
            RecentSearchRequestPayload(
                scopeMode: .allIndexed,
                scopes: [],
                resultCap: 100,
                includeHidden: false,
                sort: .lastUsedDateDescending,
            ),
        )

        let result = await invoke { reply in
            sut.recentSearch(requestData, withReply: reply)
        }

        XCTAssertNil(result.error)
        let decoded = try XCTUnwrap(result.data).decoded(as: RecentSearchResponsePayload.self)
        XCTAssertEqual(decoded, expected)
    }

    func testTagDispatchDecodesRequestCallsServiceAndEncodesReply() async throws {
        let expected = TagSearchResponsePayload(
            requestedTag: "Work",
            items: [makeEntry(fullPath: "/tmp/tagged.txt")],
        )
        let service = StubSearchExecutionService(
            onRecent: { _ in .init(items: []) },
            onTag: { request in
                XCTAssertEqual(request.requestedTag, "Work")
                XCTAssertTrue(request.exactTagVerification)
                return expected
            },
        )
        let sut = XPCSearchService(service: service, logger: .init(label: "test"))

        let requestData = try JSONEncoder().encode(
            TagSearchRequestPayload(
                requestedTag: "Work",
                scopeMode: .allIndexed,
                scopes: [],
                resultCap: 100,
                includeHidden: false,
                sort: .lastUsedDateDescending,
                exactTagVerification: true,
            ),
        )

        let result = await invoke { reply in
            sut.tagSearch(requestData, withReply: reply)
        }

        XCTAssertNil(result.error)
        let decoded = try XCTUnwrap(result.data).decoded(as: TagSearchResponsePayload.self)
        XCTAssertEqual(decoded, expected)
    }

    func testRecentDispatchMapsInvalidRequestToNSError() async {
        let service = StubSearchExecutionService(
            onRecent: { _ in .init(items: []) },
            onTag: { _ in .init(requestedTag: "", items: []) },
        )
        let sut = XPCSearchService(service: service, logger: .init(label: "test"))

        let result = await invoke { reply in
            sut.recentSearch(Data("bad-json".utf8), withReply: reply)
        }

        XCTAssertNil(result.data)
        let error = try? XCTUnwrap(result.error)
        XCTAssertEqual(error?.domain, "Voyager.FilterSearchXPC")
        XCTAssertEqual(error?.code, 1001)
    }

    func testTagDispatchMapsExecutionFailureToNSError() async throws {
        struct StubFailure: Error {}

        let service = StubSearchExecutionService(
            onRecent: { _ in .init(items: []) },
            onTag: { _ in throw StubFailure() },
        )
        let sut = XPCSearchService(service: service, logger: .init(label: "test"))
        let requestData = try JSONEncoder().encode(
            TagSearchRequestPayload(
                requestedTag: "Work",
                scopeMode: .allIndexed,
                scopes: [],
                resultCap: 100,
                includeHidden: false,
                sort: .lastUsedDateDescending,
                exactTagVerification: true,
            ),
        )

        let result = await invoke { reply in
            sut.tagSearch(requestData, withReply: reply)
        }

        XCTAssertNil(result.data)
        let error = try? XCTUnwrap(result.error)
        XCTAssertEqual(error?.domain, "Voyager.FilterSearchXPC")
        XCTAssertEqual(error?.code, 1003)
    }

    private func invoke(
        _ body: (@escaping (Data?, NSError?) -> Void) -> Void,
    ) async -> (data: Data?, error: NSError?) {
        await withCheckedContinuation { continuation in
            body { data, error in
                continuation.resume(returning: (data, error))
            }
        }
    }

    private func makeEntry(fullPath: String) -> SearchEntryPayload {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return SearchEntryPayload(
            name: URL(fileURLWithPath: fullPath).lastPathComponent,
            fullPath: fullPath,
            isFolder: false,
            isHidden: false,
            size: 1,
            modifiedDate: date,
            fileExtension: "txt",
            createdDate: date,
            addedDate: date,
            lastOpenedDate: date,
            kind: "Text",
            creatorApplication: nil,
            tags: nil,
            supplementaryMetadata: nil,
        )
    }
}

private struct StubSearchExecutionService: SearchExecutionServicing {
    var onRecent: @Sendable (RecentSearchRequestPayload) async throws -> RecentSearchResponsePayload
    var onTag: @Sendable (TagSearchRequestPayload) async throws -> TagSearchResponsePayload

    private struct UnexpectedApplyFiltersCall: Error {}

    func applyFilters(_ filters: SearchFiltersPayload) async throws -> SearchResponsePayload {
        _ = filters
        throw UnexpectedApplyFiltersCall()
    }

    func searchRecent(_ request: RecentSearchRequestPayload) async throws -> RecentSearchResponsePayload {
        try await onRecent(request)
    }

    func searchTag(_ request: TagSearchRequestPayload) async throws -> TagSearchResponsePayload {
        try await onTag(request)
    }
}

private extension Data {
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: self)
    }
}
