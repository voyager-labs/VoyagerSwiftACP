import ComposableArchitecture
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

    /// EVM-001-reload_directory_page_on_external_change: directory loader uses injected favorite color.
    /// Directory refresh must resolve favorite tags before detached filesystem work begins.
    /// - 검증 내용: EntryLoadingLive.loadItems가 주입된 favorite 색상으로 directory entry를 정규화하는지 확인
    /// - 사전 조건: 임시 directory 파일에 색상 없는 태그가 저장되고 favorite client가 같은 이름의 색상을 반환함
    /// - 기대 결과: directory loader 결과의 태그가 주입된 favorite 색상으로 정규화됨
    func testDirectoryAdapterUsesInjectedFavoriteTagColor() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerEntryLoading-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Tagged.txt")
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)
        let tagName = "InjectedFavorite"
        let favoriteTag = Tag(name: tagName, colorCode: 6)
        try TagMetadataClient.setTags([Tag(name: tagName, colorCode: 0)], for: fileURL)

        let items = try? await withDependencies {
            $0.finderFavoritesTagClient = FinderFavoritesTagClient(
                favoriteTagNames: { [tagName] },
                favoriteTags: { [favoriteTag] },
            )
        } operation: {
            try await EntryLoadingLive.loadItems(directory, true)
        }

        XCTAssertEqual(items?.first?.facets.tags, [favoriteTag])
    }

    /// EVM-001-reload_directory_page_on_external_change: Recents loader uses injected favorite color.
    /// Recents refresh must normalize helper payload tags with the scoped favorite client.
    /// - 검증 내용: Recents loader가 주입된 favorite 색상으로 payload tag를 정규화하는지 확인
    /// - 사전 조건: Recents search closure가 색상 없는 동일 이름 tag payload를 반환함
    /// - 기대 결과: Recents 결과의 태그가 주입된 favorite 색상으로 정규화됨
    func testRecentAdapterUsesInjectedFavoriteTagColor() async {
        let tagName = "InjectedFavorite"
        let favoriteTag = Tag(name: tagName, colorCode: 6)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let items = await withDependencies {
            $0.finderFavoritesTagClient = FinderFavoritesTagClient(
                favoriteTagNames: { [tagName] },
                favoriteTags: { [favoriteTag] },
            )
        } operation: {
            await EntryLoadingLive.loadRecentItemsViaSearch(showHidden: false) { _ in
                RecentSearchResponsePayload(
                    items: [
                        SearchEntryPayload(
                            name: "Recent.txt",
                            fullPath: "/tmp/Recent.txt",
                            isFolder: false,
                            isHidden: false,
                            size: 1,
                            modifiedDate: date,
                            fileExtension: "txt",
                            createdDate: date,
                            addedDate: date,
                            lastOpenedDate: nil,
                            kind: "Text",
                            creatorApplication: nil,
                            tags: [SearchTagPayload(name: tagName, colorCode: 0)],
                            supplementaryMetadata: nil,
                        ),
                    ],
                )
            }
        }

        XCTAssertEqual(items.first?.facets.tags, [favoriteTag])
    }

    /// EVM-001-reload_directory_page_on_external_change: tag-search loader uses injected favorite color.
    /// Tag route refresh must normalize helper payload tags with the scoped favorite client.
    /// - 검증 내용: Tag search loader가 주입된 favorite 색상으로 payload tag를 정규화하는지 확인
    /// - 사전 조건: Tag search closure가 색상 없는 동일 이름 tag payload를 반환함
    /// - 기대 결과: Tag search 결과의 태그가 주입된 favorite 색상으로 정규화됨
    func testTagAdapterUsesInjectedFavoriteTagColor() async {
        let tagName = "InjectedFavorite"
        let favoriteTag = Tag(name: tagName, colorCode: 6)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let items = await withDependencies {
            $0.finderFavoritesTagClient = FinderFavoritesTagClient(
                favoriteTagNames: { [tagName] },
                favoriteTags: { [favoriteTag] },
            )
        } operation: {
            await EntryLoadingLive.loadFilesWithTagViaSearch(tag: tagName, showHidden: false) { request in
                TagSearchResponsePayload(
                    requestedTag: request.requestedTag,
                    items: [
                        SearchEntryPayload(
                            name: "Tagged.txt",
                            fullPath: "/tmp/Tagged.txt",
                            isFolder: false,
                            isHidden: false,
                            size: 1,
                            modifiedDate: date,
                            fileExtension: "txt",
                            createdDate: date,
                            addedDate: date,
                            lastOpenedDate: nil,
                            kind: "Text",
                            creatorApplication: nil,
                            tags: [SearchTagPayload(name: tagName, colorCode: 0)],
                            supplementaryMetadata: nil,
                        ),
                    ],
                )
            }
        }

        XCTAssertEqual(items.first?.facets.tags, [favoriteTag])
    }
}
