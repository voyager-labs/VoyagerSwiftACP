import Foundation
@testable import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared
import XCTest

@MainActor
final class EVM001NavigatePagesEntryLoadingAdapterTests: XCTestCase {
    // MARK: - EVM-001-reload_directory_page_on_external_change

    /// EVM-001-reload_directory_page_on_external_change: Recents route loader maps helper payloads into entry models.
    /// Recents/Tags/Computer route refresh keeps route identity while refreshing the route-specific loader output.
    /// - 검증 내용: Recent search helper payload request options and EntryModel facet mapping
    /// - 사전 조건: Recents loader receives a helper response with tag, last-opened, creator, and supplementary metadata
    /// - 기대 결과: Helper payload fields are preserved on the resulting EntryModel used by the refreshed route
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
                            supplementaryMetadata: .compressedFileSize(12),
                        ),
                    ],
                )
            },
        )

        XCTAssertEqual(items.map(\.fullPath), ["/tmp/Recent.txt"])
        XCTAssertEqual(items.first?.facets.lastOpenedDate, date)
        XCTAssertEqual(items.first?.facets.tags, [Tag(name: "Work", colorCode: 4)])
        XCTAssertEqual(items.first?.facets.creatorApplication, "TextEdit")
    }

    /// EVM-001-reload_directory_page_on_external_change: Tags route loader falls back to an empty result on helper
    /// failure.
    /// Recents/Tags route refresh must not crash or mutate route identity when the route-specific helper fails.
    /// - 검증 내용: Tags helper failure fallback behavior
    /// - 사전 조건: Tags route loader receives a failing helper search dependency
    /// - 기대 결과: Loader returns an empty entry list for the failed refresh
    func testTagAdapterReturnsEmptyArrayOnHelperFailure() async {
        struct StubError: Error {}

        let items = await EntryLoadingLive.loadFilesWithTagViaSearch(
            tag: "Work",
            showHidden: false,
            search: { _ in throw StubError() },
        )

        XCTAssertEqual(items, [])
    }

    /// EVM-001-reload_directory_page_on_external_change: Tags route loader maps helper payloads into entry models.
    /// Tags route refresh keeps the route-specific requested tag and entry tag color data intact.
    /// - 검증 내용: Tags helper request contract and SearchEntryPayload to EntryModel tag facet mapping
    /// - 사전 조건: Tags route loader refreshes the Green tag route from a helper response
    /// - 기대 결과: Requested tag and color-coded entry tag facets are preserved in the loaded entries
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
                            supplementaryMetadata: nil,
                        ),
                    ],
                )
            },
        )

        XCTAssertEqual(items.map(\.fullPath), ["/tmp/Tagged.txt"])
        XCTAssertEqual(items.first?.facets.tags, [Tag(name: "Green", colorCode: 2)])
    }
}
