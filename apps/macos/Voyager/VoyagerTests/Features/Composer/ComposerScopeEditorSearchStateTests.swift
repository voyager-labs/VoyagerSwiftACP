import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesEntry
import XCTest

@MainActor
final class ComposerScopeEditorSearchStateTests: XCTestCase {
    func testScopeEditorSearchQueryImmediatelyShowsSearchResultsAndClearsCandidates() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.candidateItems = [
            ComposerScopeEditorCandidateItem(
                path: "/Users/test/Documents",
                name: "Documents",
                iconName: "folder",
                locationIdentifier: "suggestions",
            ),
        ]

        let store = makePassiveStore(initialState: initialState)

        await store.send(.scopeEditorSetQueryText("docs")) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.queryText = "docs"
            $0.scopeEditor.listState = .searchResults(query: "docs")
            $0.scopeEditor.candidateItems = []
        }

        await store.send(.scopeEditorSetQueryText("")) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        await store.finish()
    }

    func testScopeEditorSearchResponseStoresCandidatesForMatchingQuery() async {
        var initialState = ComposerState()
        initialState.scopeEditor.queryText = "docs"
        initialState.scopeEditor.listState = .searchResults(query: "docs")

        let store = makePassiveStore(initialState: initialState)

        await store.send(
            .scopeEditorSearchResponse(
                "docs",
                .success([
                    ComposerScopeUtils.DirectoryItem(
                        id: "/Users/test/Documents",
                        path: "/Users/test/Documents",
                        name: "Documents",
                        iconName: "folder",
                    ),
                ]),
            ),
        ) {
            $0.scopeEditor.queryText = "docs"
            $0.scopeEditor.listState = .searchResults(query: "docs")
            $0.scopeEditor.candidateItems = [
                ComposerScopeEditorCandidateItem(
                    path: "/Users/test/Documents",
                    name: "Documents",
                    iconName: "folder",
                    locationIdentifier: nil,
                ),
            ]
        }
    }

    func testScopeEditorSearchResponseIgnoresStaleQuery() async {
        var initialState = ComposerState()
        initialState.scopeEditor.queryText = "docs"
        initialState.scopeEditor.listState = .searchResults(query: "docs")

        let store = makePassiveStore(initialState: initialState)

        await store.send(
            .scopeEditorSearchResponse(
                "stale",
                .success([
                    ComposerScopeUtils.DirectoryItem(
                        id: "/Users/test/Downloads",
                        path: "/Users/test/Downloads",
                        name: "Downloads",
                        iconName: "folder",
                    ),
                ]),
            ),
        ) {
            $0.scopeEditor.queryText = "docs"
            $0.scopeEditor.listState = .searchResults(query: "docs")
            $0.scopeEditor.candidateItems = []
        }
    }

    func testScopeEditorSearchNoResultsShowsNoResultsState() async {
        var initialState = ComposerState()
        initialState.scopeEditor.queryText = "docs"
        initialState.scopeEditor.listState = .searchResults(query: "docs")

        let store = makePassiveStore(initialState: initialState)

        await store.send(
            .scopeEditorSearchResponse(
                "docs",
                .success([]),
            ),
        ) {
            $0.scopeEditor.queryText = "docs"
            $0.scopeEditor.listState = .noResults(query: "docs")
            $0.scopeEditor.candidateItems = []
        }
    }

    func testScopeEditorSearchFailureShowsNoResultsState() async {
        struct SearchFailure: Error, Equatable {}

        var initialState = ComposerState()
        initialState.scopeEditor.queryText = "docs"
        initialState.scopeEditor.listState = .searchResults(query: "docs")
        initialState.scopeEditor.candidateItems = [
            ComposerScopeEditorCandidateItem(
                path: "/Users/test/Old",
                name: "Old",
                iconName: "folder",
                locationIdentifier: nil,
            ),
        ]

        let store = makePassiveStore(initialState: initialState)

        await store.send(
            .scopeEditorSearchResponse(
                "docs",
                .failure(SearchFailure()),
            ),
        ) {
            $0.scopeEditor.queryText = "docs"
            $0.scopeEditor.listState = .noResults(query: "docs")
            $0.scopeEditor.candidateItems = []
        }
    }

    func testScopeEditorStaleFailureResponseDoesNotMutateState() async {
        struct SearchFailure: Error, Equatable {}

        var initialState = ComposerState()
        initialState.scopeEditor.queryText = "docs"
        initialState.scopeEditor.listState = .searchResults(query: "docs")
        initialState.scopeEditor.candidateItems = [
            ComposerScopeEditorCandidateItem(
                path: "/Users/test/Documents",
                name: "Documents",
                iconName: "folder",
                locationIdentifier: nil,
            ),
        ]

        let store = makePassiveStore(initialState: initialState)

        await store.send(
            .scopeEditorSearchResponse(
                "stale",
                .failure(SearchFailure()),
            ),
        ) {
            $0.scopeEditor.queryText = "docs"
            $0.scopeEditor.listState = .searchResults(query: "docs")
            $0.scopeEditor.candidateItems = [
                ComposerScopeEditorCandidateItem(
                    path: "/Users/test/Documents",
                    name: "Documents",
                    iconName: "folder",
                    locationIdentifier: nil,
                ),
            ]
        }
    }

    func testScopeEditorClearSearchInAddModeReturnsToDefaultCandidates() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.queryText = "docs"
        initialState.scopeEditor.listState = .searchResults(query: "docs")

        let store = makePassiveStore(initialState: initialState)

        await store.send(.scopeEditorSetQueryText("")) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        await store.finish()
    }

    func testScopeEditorClearSearchInEditModeReturnsToChildFolders() async throws {
        let fixture = try makeEditModeChildFolderFixture()
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.editingPath = fixture.parentURL.path
        initialState.scopeEditor.entryMode = .edit
        initialState.scopeEditor.queryText = "do"
        initialState.scopeEditor.listState = .searchResults(query: "do")

        let store = makeEditModeChildFolderStore(initialState: initialState, fixture: fixture)

        await store.send(.scopeEditorSetQueryText("")) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = fixture.parentURL.path
            $0.scopeEditor.entryMode = .edit
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.listState = .childFolders(parentPath: fixture.parentURL.path)
            $0.scopeEditor.candidateItems = [
                ComposerScopeEditorCandidateItem(
                    path: fixture.archiveURL.path,
                    name: "Archive",
                    iconName: "folder",
                    locationIdentifier: fixture.parentURL.path,
                ),
                ComposerScopeEditorCandidateItem(
                    path: fixture.receiptsURL.path,
                    name: "Receipts",
                    iconName: "folder",
                    locationIdentifier: fixture.parentURL.path,
                ),
            ]
        }

        await store.finish()
    }

    func testScopeEditorFastInputDeleteIgnoresStaleSearchResponses() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true

        let store = makePassiveStore(initialState: initialState)

        await store.send(.scopeEditorSetQueryText("d")) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.queryText = "d"
            $0.scopeEditor.listState = .searchResults(query: "d")
            $0.scopeEditor.candidateItems = []
        }

        await store.send(.scopeEditorSetQueryText("do")) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.queryText = "do"
            $0.scopeEditor.listState = .searchResults(query: "do")
            $0.scopeEditor.candidateItems = []
        }

        await store.send(.scopeEditorSetQueryText("")) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        await store.send(staleDesktopSearchResponse(query: "d")) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        await store.send(
            .scopeEditorSearchResponse(
                "do",
                .failure(CancellationError()),
            ),
        ) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        await store.finish()
    }
}

private func staleDesktopSearchResponse(query: String) -> ComposerAction {
    .scopeEditorSearchResponse(
        query,
        .success([
            ComposerScopeUtils.DirectoryItem(
                id: "/Users/test/Desktop",
                path: "/Users/test/Desktop",
                name: "Desktop",
                iconName: "folder",
            ),
        ]),
    )
}

private struct EditModeChildFolderFixture {
    let temporaryRoot: URL
    let parentURL: URL
    let archiveURL: URL
    let receiptsURL: URL
}

private func makeEditModeChildFolderFixture() throws -> EditModeChildFolderFixture {
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let parentURL = temporaryRoot.appendingPathComponent("Parent", isDirectory: true)
    let archiveURL = parentURL.appendingPathComponent("Archive", isDirectory: true)
    let receiptsURL = parentURL.appendingPathComponent("Receipts", isDirectory: true)
    try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: receiptsURL, withIntermediateDirectories: true)
    return EditModeChildFolderFixture(
        temporaryRoot: temporaryRoot,
        parentURL: parentURL,
        archiveURL: archiveURL,
        receiptsURL: receiptsURL,
    )
}

private func makeEditModeChildFolderStore(
    initialState: ComposerState,
    fixture: EditModeChildFolderFixture,
) -> TestStore<ComposerState, ComposerAction> {
    var entryLoadingClient: VoyagerEntitiesEntry.EntryLoadingClient = .testValue
    entryLoadingClient.contentsOfDirectory = { url, keys, options in
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: options,
        )
    }
    entryLoadingClient.displayName = { ($0 as NSString).lastPathComponent }
    entryLoadingClient.homeDirectory = { fixture.temporaryRoot.path }

    return TestStore(initialState: initialState) {
        ComposerFeature()
    } withDependencies: {
        $0.searchClient = .testValue
        $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = entryLoadingClient
    }
}

private func makePassiveStore(initialState: ComposerState) -> TestStore<ComposerState, ComposerAction> {
    TestStore(initialState: initialState) {
        ComposerFeature()
    } withDependencies: {
        $0.searchClient = .testValue
        $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
    }
}
