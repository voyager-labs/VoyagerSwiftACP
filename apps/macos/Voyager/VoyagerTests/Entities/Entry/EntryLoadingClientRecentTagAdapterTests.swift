import Foundation
@testable import Voyager
import XCTest

@MainActor
final class EntryLoadingClientRecentTagAdapterTests: XCTestCase {
    func testRecentAdapterMapsHelperPayloadIntoEntryModel() async {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let searchClient = SearchClient(
            search: { _ in .init(itemCount: 0, appliedFilters: nil, items: nil, error: nil) },
            applyFilters: { _ in .init(itemCount: 0, appliedFilters: nil, items: nil, error: nil) },
            recentSearch: { request in
                XCTAssertEqual(request.scopeMode, .allIndexed)
                XCTAssertEqual(request.resultCap, 100)
                XCTAssertFalse(request.includeHidden)
                return RecentSearchResponsePayload(
                    items: [
                        SearchEntryPayload(
                            name: "Recent.txt",
                            fullPath: "/tmp/Recent.txt",
                            isFolder: false,
                            isHidden: false,
                            size: 12,
                            modifiedDate: date,
                            fileExtension: "txt",
                            createdDate: date,
                            addedDate: date,
                            lastOpenedDate: date,
                            kind: "Text",
                            creatorApplication: "TextEdit",
                            tags: [SearchTagPayload(name: "Work", colorCode: 4)],
                            supplementaryMetadata: .compressedFileSize(12),
                        ),
                    ],
                )
            },
            tagSearch: { request in
                .init(requestedTag: request.requestedTag, items: [])
            },
        )

        let items = await EntryLoadingLive.loadRecentItemsViaSearch(showHidden: false, searchClient: searchClient)

        XCTAssertEqual(items.map(\.fullPath), ["/tmp/Recent.txt"])
        XCTAssertEqual(items.first?.facets.lastOpenedDate, date)
        XCTAssertEqual(items.first?.facets.tags, [Tag(name: "Work", colorCode: 4)])
        XCTAssertEqual(items.first?.facets.creatorApplication, "TextEdit")
    }

    func testTagAdapterReturnsEmptyArrayOnHelperFailure() async {
        struct StubError: Error {}

        let searchClient = SearchClient(
            search: { _ in .init(itemCount: 0, appliedFilters: nil, items: nil, error: nil) },
            applyFilters: { _ in .init(itemCount: 0, appliedFilters: nil, items: nil, error: nil) },
            recentSearch: { _ in .init(items: []) },
            tagSearch: { _ in throw StubError() },
        )

        let items = await EntryLoadingLive.loadFilesWithTagViaSearch(
            tag: "Work",
            showHidden: false,
            searchClient: searchClient,
        )

        XCTAssertEqual(items, [])
    }
}
