import Darwin
import Foundation
@testable import VoyagerHelper
import VoyagerShared
import XCTest

@MainActor
final class HelperRecentTagSearchSemanticsTests: XCTestCase {
    func testRecentResponseFiltersHiddenAndDeletedEntriesAndSortsByLastUsedDate() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let visibleOld = sandbox.appendingPathComponent("old.txt")
        let visibleNew = sandbox.appendingPathComponent("new.txt")
        let hidden = sandbox.appendingPathComponent(".hidden.txt")
        let deleted = sandbox.appendingPathComponent("deleted.txt")

        try Data("old".utf8).write(to: visibleOld)
        try Data("new".utf8).write(to: visibleNew)
        try Data("hidden".utf8).write(to: hidden)

        let service = SpotlightSearchService()
        let response = service.makeRecentResponse(
            from: [
                .init(path: visibleOld.path, lastUsedDate: Date(timeIntervalSince1970: 10), rawUserTags: []),
                .init(path: hidden.path, lastUsedDate: Date(timeIntervalSince1970: 30), rawUserTags: []),
                .init(path: visibleNew.path, lastUsedDate: Date(timeIntervalSince1970: 20), rawUserTags: []),
                .init(path: deleted.path, lastUsedDate: Date(timeIntervalSince1970: 40), rawUserTags: []),
            ],
            request: .init(
                scopeMode: .allIndexed,
                scopes: [],
                resultCap: 100,
                includeHidden: false,
                sort: .lastUsedDateDescending,
            ),
        )

        XCTAssertEqual(response.items.map(\.fullPath), [visibleNew.path, visibleOld.path])
        XCTAssertEqual(
            response.items.map(\.lastOpenedDate),
            [Date(timeIntervalSince1970: 20), Date(timeIntervalSince1970: 10)],
        )
    }

    func testTagResponsePerformsExactVerificationAndPreservesTagColorMetadata() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let exact = sandbox.appendingPathComponent("exact.txt")
        let falsePositive = sandbox.appendingPathComponent("false-positive.txt")

        try Data("exact".utf8).write(to: exact)
        try Data("false".utf8).write(to: falsePositive)

        let service = SpotlightSearchService()
        let response = service.makeTagResponse(
            from: [
                .init(
                    path: falsePositive.path,
                    lastUsedDate: Date(timeIntervalSince1970: 30),
                    rawUserTags: ["Workspace\n7"],
                ),
                .init(
                    path: exact.path,
                    lastUsedDate: Date(timeIntervalSince1970: 20),
                    rawUserTags: ["Work\n4", "Personal\n2"],
                ),
            ],
            request: .init(
                requestedTag: "Work",
                scopeMode: .allIndexed,
                scopes: [],
                resultCap: 100,
                includeHidden: false,
                sort: .lastUsedDateDescending,
                exactTagVerification: true,
            ),
        )

        XCTAssertEqual(response.requestedTag, "Work")
        XCTAssertEqual(response.items.map(\.fullPath), [exact.path])
        XCTAssertEqual(response.items.first?.tags, [
            SearchTagPayload(name: "Work", colorCode: 4),
            SearchTagPayload(name: "Personal", colorCode: 2),
        ])
    }

    func testTagResponseExactVerificationIsCaseInsensitive() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let tagged = sandbox.appendingPathComponent("tagged.txt")
        try Data("tagged".utf8).write(to: tagged)

        let service = SpotlightSearchService()
        let response = service.makeTagResponse(
            from: [
                .init(
                    path: tagged.path,
                    lastUsedDate: Date(timeIntervalSince1970: 20),
                    rawUserTags: ["Work\n4"],
                ),
            ],
            request: .init(
                requestedTag: "work",
                scopeMode: .allIndexed,
                scopes: [],
                resultCap: 100,
                includeHidden: false,
                sort: .lastUsedDateDescending,
                exactTagVerification: true,
            ),
        )

        XCTAssertEqual(response.items.map(\.fullPath), [tagged.path])
    }

    func testTagResponseLoadsColorPreservingFallbackWhenMatchRawUserTagsIsEmpty() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let tagged = sandbox.appendingPathComponent("tagged.txt")
        try Data("tagged".utf8).write(to: tagged)

        let service = SpotlightSearchService(rawUserTagsLoader: { url in
            XCTAssertEqual(url, tagged)
            return ["Green\n2"]
        })
        let response = service.makeTagResponse(
            from: [
                .init(
                    path: tagged.path,
                    lastUsedDate: Date(timeIntervalSince1970: 20),
                    rawUserTags: [],
                ),
            ],
            request: .init(
                requestedTag: "Green",
                scopeMode: .allIndexed,
                scopes: [],
                resultCap: 100,
                includeHidden: false,
                sort: .lastUsedDateDescending,
                exactTagVerification: true,
            ),
        )

        XCTAssertEqual(response.items.map(\.fullPath), [tagged.path])
        XCTAssertEqual(response.items.first?.tags, [SearchTagPayload(name: "Green", colorCode: 2)])
    }

    func testTagResponsePrefersReloadedColorPreservingTagsOverNameOnlyMatchTags() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let tagged = sandbox.appendingPathComponent("tagged.txt")
        try Data("tagged".utf8).write(to: tagged)

        let service = SpotlightSearchService(rawUserTagsLoader: { url in
            XCTAssertEqual(url, tagged)
            return ["Green\n2"]
        })
        let response = service.makeTagResponse(
            from: [
                .init(
                    path: tagged.path,
                    lastUsedDate: Date(timeIntervalSince1970: 20),
                    rawUserTags: ["Green"],
                ),
            ],
            request: .init(
                requestedTag: "Green",
                scopeMode: .allIndexed,
                scopes: [],
                resultCap: 100,
                includeHidden: false,
                sort: .lastUsedDateDescending,
                exactTagVerification: true,
            ),
        )

        XCTAssertEqual(response.items.map(\.fullPath), [tagged.path])
        XCTAssertEqual(response.items.first?.tags, [SearchTagPayload(name: "Green", colorCode: 2)])
    }

    func testRecentResponseDoesNotManufactureNeutralTagsWhenRawMetadataIsUnavailable() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let file = sandbox.appendingPathComponent("untagged.txt")
        try Data("plain".utf8).write(to: file)

        let service = SpotlightSearchService(rawUserTagsLoader: { _ in [] })
        let response = service.makeRecentResponse(
            from: [
                .init(path: file.path, lastUsedDate: Date(timeIntervalSince1970: 10), rawUserTags: []),
            ],
            request: .init(
                scopeMode: .allIndexed,
                scopes: [],
                resultCap: 100,
                includeHidden: false,
                sort: .lastUsedDateDescending,
            ),
        )

        XCTAssertEqual(response.items.map(\.fullPath), [file.path])
        XCTAssertNil(response.items.first?.tags)
    }

    func testLoadRawUserTags_ReadsColorPreservingXattrData() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let tagged = sandbox.appendingPathComponent("tagged.txt")
        try Data("tagged".utf8).write(to: tagged)

        let tagData = try PropertyListSerialization.data(
            fromPropertyList: ["Green\n2", "Orange\n7"],
            format: .binary,
            options: 0,
        )

        let result = setxattr(
            tagged.path,
            "com.apple.metadata:_kMDItemUserTags",
            (tagData as NSData).bytes,
            tagData.count,
            0,
            XATTR_NOFOLLOW,
        )
        XCTAssertEqual(result, 0)

        XCTAssertEqual(
            SpotlightSearchService.loadRawUserTags(from: tagged),
            ["Green\n2", "Orange\n7"],
        )
    }

    func testFilterPathsKeepsOnlyDirectChildrenWhenSubfoldersDisabled() throws {
        let service = SpotlightSearchService()

        let filtered = service.filterPaths(
            [
                "/tmp/root/file.txt",
                "/tmp/root/nested/deeper.txt",
                "/tmp/other/file.txt",
            ],
            scopes: ["/tmp/root"],
            includeSubfolders: false,
        )

        XCTAssertEqual(filtered, ["/tmp/root/file.txt"])
    }

    func testExactFolderPathMatcherUsesDirectParentOnly() throws {
        let service = SpotlightSearchService()
        let scopes = SearchScopeNormalizer.normalizeScopes(["/tmp/root"])

        XCTAssertTrue(service.pathMatchesExactFolderScope("/tmp/root/file.txt", normalizedScopes: scopes))
        XCTAssertFalse(service.pathMatchesExactFolderScope("/tmp/root/nested/deeper.txt", normalizedScopes: scopes))
        XCTAssertFalse(service.pathMatchesExactFolderScope("/tmp/rootSibling/file.txt", normalizedScopes: scopes))
    }

    private func makeSandbox() throws -> URL {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        return sandbox
    }
}
