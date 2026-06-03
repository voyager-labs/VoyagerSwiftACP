import Foundation
@testable import Voyager
import VoyagerEntitiesEntry
import XCTest

final class ComposerScopeDirectorySearchRankingTests: XCTestCase {
    func testScopeDirectorySearchRanksExactAndPrefixMatchesBeforeEarlierSubstringMatches() async throws {
        let fixture = try makeSearchRankingFixture(query: "voyscopeapp")
        let previousCurrentDirectory = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(fixture.temporaryRoot.path)
        defer {
            FileManager.default.changeCurrentDirectoryPath(previousCurrentDirectory)
            try? FileManager.default.removeItem(at: fixture.temporaryRoot)
        }

        let results = try await ComposerScopeUtils.searchDirectories(
            query: "voyscopeapp",
            entryLoadingClient: makeSearchRankingEntryLoadingClient(fixture: fixture),
            maxResults: 3,
            initialMaxDepth: 2,
            timeout: 2.0,
        )

        XCTAssertEqual(
            results.map(\.name),
            ["voyscopeapp", "voyscopeappKit", "My-voyscopeapp"],
        )
    }
}

private struct SearchRankingFixture {
    let temporaryRoot: URL
    let documentsURL: URL
    let weakMatchURLs: [URL]
    let exactMatchURL: URL
    let prefixMatchURL: URL
    let wordBoundaryMatchURL: URL
}

private func makeSearchRankingFixture(query: String) throws -> SearchRankingFixture {
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let documentsURL = temporaryRoot.appendingPathComponent("Documents", isDirectory: true)
    let weakMatchURLs = [
        temporaryRoot.appendingPathComponent("aaa-" + query, isDirectory: true),
        temporaryRoot.appendingPathComponent("bbb-" + query, isDirectory: true),
        temporaryRoot.appendingPathComponent("ccc-" + query, isDirectory: true),
    ]
    let exactMatchURL = documentsURL.appendingPathComponent(query, isDirectory: true)
    let prefixMatchURL = documentsURL.appendingPathComponent(query + "Kit", isDirectory: true)
    let wordBoundaryMatchURL = documentsURL.appendingPathComponent("My-" + query, isDirectory: true)

    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    for url in weakMatchURLs {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    try FileManager.default.createDirectory(at: exactMatchURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: prefixMatchURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: wordBoundaryMatchURL, withIntermediateDirectories: true)

    return SearchRankingFixture(
        temporaryRoot: temporaryRoot,
        documentsURL: documentsURL,
        weakMatchURLs: weakMatchURLs,
        exactMatchURL: exactMatchURL,
        prefixMatchURL: prefixMatchURL,
        wordBoundaryMatchURL: wordBoundaryMatchURL,
    )
}

private func makeSearchRankingEntryLoadingClient(
    fixture: SearchRankingFixture,
) -> VoyagerEntitiesEntry.EntryLoadingClient {
    var entryLoadingClient: VoyagerEntitiesEntry.EntryLoadingClient = .testValue
    entryLoadingClient.contentsOfDirectory = { url, keys, options in
        if url.path == fixture.temporaryRoot.path {
            return fixture.weakMatchURLs + [fixture.documentsURL]
        }
        if url.path == fixture.documentsURL.path {
            return [
                fixture.exactMatchURL,
                fixture.prefixMatchURL,
                fixture.wordBoundaryMatchURL,
            ]
        }

        return try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: options,
        )
    }
    entryLoadingClient.displayName = { ($0 as NSString).lastPathComponent }
    entryLoadingClient.homeDirectory = { fixture.temporaryRoot.path }
    entryLoadingClient.urlsForDirectory = { _, _ in [] }
    return entryLoadingClient
}
