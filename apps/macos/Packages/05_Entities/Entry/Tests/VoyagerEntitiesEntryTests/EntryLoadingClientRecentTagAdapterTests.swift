import Foundation
@testable import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared
import XCTest

@MainActor
final class EntryLoadingClientRecentTagAdapterTests: XCTestCase {
    func testRecentAdapterMapsHelperPayloadIntoEntryModel() async {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let items = await EntryLoadingLive.loadRecentItemsViaSearch(
            showHidden: false,
            search: { request in
                XCTAssertEqual(request.scopeMode, .allIndexed)
                XCTAssertEqual(request.resultCap, 100)
                XCTAssertFalse(request.includeHidden)
                return VoyagerShared.RecentSearchResponsePayload(
                    items: [
                        VoyagerShared.SearchEntryPayload(
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
                            tags: [VoyagerShared.SearchTagPayload(name: "Work", colorCode: 4)],
                            supplementaryMetadata: .compressedFileSize(12)
                        ),
                    ]
                )
            }
        )

        XCTAssertEqual(items.map(\.fullPath), ["/tmp/Recent.txt"])
        XCTAssertEqual(items.first?.facets.lastOpenedDate, date)
        XCTAssertEqual(items.first?.facets.tags, [Tag(name: "Work", colorCode: 4)])
        XCTAssertEqual(items.first?.facets.creatorApplication, "TextEdit")
    }

    func testTagAdapterReturnsEmptyArrayOnHelperFailure() async {
        struct StubError: Error {}

        let items = await EntryLoadingLive.loadFilesWithTagViaSearch(
            tag: "Work",
            showHidden: false,
            search: { _ in throw StubError() }
        )

        XCTAssertEqual(items, [])
    }

    func testTagAdapterMapsHelperPayloadIntoEntryModel() async {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let items = await EntryLoadingLive.loadFilesWithTagViaSearch(
            tag: "Green",
            showHidden: false,
            search: { request in
                XCTAssertEqual(request.requestedTag, "Green")
                XCTAssertTrue(request.exactTagVerification)
                return VoyagerShared.TagSearchResponsePayload(
                    requestedTag: request.requestedTag,
                    items: [
                        VoyagerShared.SearchEntryPayload(
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
                            tags: [VoyagerShared.SearchTagPayload(name: "Green", colorCode: 2)],
                            supplementaryMetadata: nil
                        ),
                    ]
                )
            }
        )

        XCTAssertEqual(items.map(\.fullPath), ["/tmp/Tagged.txt"])
        XCTAssertEqual(items.first?.facets.tags, [Tag(name: "Green", colorCode: 2)])
    }
}
