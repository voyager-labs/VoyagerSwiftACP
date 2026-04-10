import Foundation
@testable import Voyager
import XCTest

@MainActor
final class EntryLoadingClientRecentTagAdapterTests: XCTestCase {
    func testRecentAdapterMapsHelperPayloadIntoEntryModel() async {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let recentSearchClient = RecentSearchClient(
            search: { request in
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
        )

        let items = await EntryLoadingLive.loadRecentItemsViaSearch(
            showHidden: false,
            recentSearchClient: recentSearchClient,
        )

        XCTAssertEqual(items.map(\.fullPath), ["/tmp/Recent.txt"])
        XCTAssertEqual(items.first?.facets.lastOpenedDate, date)
        XCTAssertEqual(items.first?.facets.tags, [Tag(name: "Work", colorCode: 4)])
        XCTAssertEqual(items.first?.facets.creatorApplication, "TextEdit")
    }

    func testTagAdapterReturnsEmptyArrayOnHelperFailure() async {
        struct StubError: Error {}

        let tagSearchClient = TagSearchClient(search: { _ in throw StubError() })

        let items = await EntryLoadingLive.loadFilesWithTagViaSearch(
            tag: "Work",
            showHidden: false,
            tagSearchClient: tagSearchClient,
        )

        XCTAssertEqual(items, [])
    }

    func testTagAdapterMapsHelperPayloadIntoEntryModel() async {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let tagSearchClient = TagSearchClient(
            search: { request in
                XCTAssertEqual(request.requestedTag, "Green")
                XCTAssertTrue(request.exactTagVerification)
                return TagSearchResponsePayload(
                    requestedTag: request.requestedTag,
                    items: [
                        SearchEntryPayload(
                            name: "Tagged.txt",
                            fullPath: "/tmp/Tagged.txt",
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
                            tags: [SearchTagPayload(name: "Green", colorCode: 2)],
                            supplementaryMetadata: nil,
                        ),
                    ],
                )
            },
        )

        let items = await EntryLoadingLive.loadFilesWithTagViaSearch(
            tag: "Green",
            showHidden: false,
            tagSearchClient: tagSearchClient,
        )

        XCTAssertEqual(items.map(\.fullPath), ["/tmp/Tagged.txt"])
        XCTAssertEqual(items.first?.facets.tags, [Tag(name: "Green", colorCode: 2)])
    }
}
