import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesEntry
import XCTest

@MainActor
final class ComposerScopeEditorChildFolderTests: XCTestCase {
    func testScopeEditorOpenInEditModeShowsDirectChildFolders() async throws {
        let fixture = try makeChildFolderFixture()
        defer { try? FileManager.default.removeItem(at: fixture.temporaryRoot) }

        let store = TestStore(initialState: makeComposerState(fixture: fixture)) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = fixture.entryLoadingClient
        }

        await store.send(.scopeEditorOpen(editingPath: fixture.editingURL.path, favorites: [], backHistory: [])) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = fixture.editingURL.path
            $0.scopeEditor.entryMode = .edit
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.listState = .childFolders(parentPath: fixture.editingURL.path)
            $0.scopeEditor.candidateItems = fixture.expectedChildCandidates
            $0.scopeEditor.favorites = []
            $0.scopeEditor.backHistory = []
        }

        XCTAssertFalse(store.state.scopeEditor.candidateItems.contains { $0.path == fixture.childCollectionURL.path })
        XCTAssertEqual(
            store.state.scopeEditor.candidateSelectionIntent(for: fixture.childReceiptsURL.path),
            .exclude(path: fixture.childReceiptsURL.path),
        )
        await store.finish()
    }

    func testScopeTreeNeighborhoodIncludesParentSiblingsAndChildrenWithoutCollectionFiles() throws {
        let fixture = try makeChildFolderFixture()
        defer { try? FileManager.default.removeItem(at: fixture.temporaryRoot) }

        let childCandidates = makeChildScopeEditorCandidates(
            parentPath: fixture.editingURL.path,
            entryLoadingClient: fixture.entryLoadingClient,
        )
        let neighborhood = makeNeighborhoodSeeds(fixture: fixture)
        let state = makeScopeEditorState(fixture: fixture, candidateItems: childCandidates)
        let rows = state.treeRows(neighborhoodSeedItems: neighborhood)

        XCTAssertEqual(neighborhood.map(\.path), [
            fixture.workspaceURL.path,
            fixture.editingURL.path,
            fixture.siblingURL.path,
        ])
        XCTAssertEqual(rows.map(\.path), [
            fixture.editingURL.path,
            fixture.childArchiveURL.path,
            fixture.childReceiptsURL.path,
            fixture.workspaceURL.path,
            fixture.siblingURL.path,
        ])
        XCTAssertFalse(rows.contains { $0.path == fixture.childCollectionURL.path })
        XCTAssertFalse(rows.contains { $0.path == fixture.workspaceCollectionURL.path })
        XCTAssertFalse(rows.contains { $0.path == fixture.workspaceFileURL.path })
        XCTAssertFalse(rows.contains { $0.path == fixture.explicitBasePeerURL.path })
        XCTAssertFalse(rows.contains { $0.path == fixture.exceptionPeerURL.path })
    }

    func testScopeTreeNeighborhoodDoesNotPersistSyntheticRowsInCandidateItems() throws {
        let fixture = try makeChildFolderFixture()
        defer { try? FileManager.default.removeItem(at: fixture.temporaryRoot) }

        let childCandidates = makeChildScopeEditorCandidates(
            parentPath: fixture.editingURL.path,
            entryLoadingClient: fixture.entryLoadingClient,
        )
        let neighborhood = makeNeighborhoodSeeds(fixture: fixture)
        let state = makeScopeEditorState(fixture: fixture, candidateItems: childCandidates)
        _ = state.treeRows(neighborhoodSeedItems: neighborhood)

        XCTAssertEqual(state.candidateItems, childCandidates)
        XCTAssertFalse(state.candidateItems.contains { $0.path == fixture.workspaceURL.path })
        XCTAssertFalse(state.candidateItems.contains { $0.path == fixture.siblingURL.path })
        XCTAssertFalse(state.candidateItems.contains { $0.path == fixture.editingURL.path })

        let rootOnlyState = ComposerScopeEditorState(
            selection: .rootOnly,
            listState: .defaultCandidates,
            isPresented: true,
            queryText: "",
            candidateItems: [childCandidates[0]],
        )
        let rootRows = rootOnlyState.treeRows(neighborhoodSeedItems: [])

        XCTAssertEqual(rootRows.first?.path, "/")
        XCTAssertEqual(rootOnlyState.candidateItems, [childCandidates[0]])
    }

    func testScopeTreeNeighborhoodDedupesEditingPathBaseExceptionAndCandidateRows() throws {
        let fixture = try makeChildFolderFixture()
        defer { try? FileManager.default.removeItem(at: fixture.temporaryRoot) }

        let childCandidates = makeChildScopeEditorCandidates(
            parentPath: fixture.editingURL.path,
            entryLoadingClient: fixture.entryLoadingClient,
        )
        let neighborhood = makeNeighborhoodSeeds(fixture: fixture) + [
            ComposerScopeTreeSeedItem(
                path: fixture.childReceiptsURL.path,
                name: "Receipts Seed",
                iconName: "folder.badge.plus",
                locationIdentifier: "seed-location",
                secondaryText: "Transient",
            ),
        ]
        let state = makeScopeEditorState(fixture: fixture, candidateItems: childCandidates)
        let rows = state.treeRows(neighborhoodSeedItems: neighborhood)
        let rowsByPath = Dictionary(uniqueKeysWithValues: rows.map { ($0.path, $0) })

        XCTAssertEqual(rows.count(where: { $0.path == fixture.editingURL.path }), 1)
        XCTAssertEqual(rowsByPath[fixture.editingURL.path]?.kind, .base)
        XCTAssertEqual(rowsByPath[fixture.childReceiptsURL.path]?.locationIdentifier, fixture.editingURL.path)
        XCTAssertNil(rowsByPath[fixture.childReceiptsURL.path]?.secondaryText)
        XCTAssertFalse(rows.contains { $0.path == fixture.explicitBasePeerURL.path })
        XCTAssertFalse(rows.contains { $0.path == fixture.exceptionPeerURL.path })
    }

    func testScopeTreeNeighborhoodOmitsParentSeedWhenParentIsRoot() {
        let selection = ComposerScopeSelection.explicit(
            bases: [ComposerScopeBase(path: "/Users")],
            exceptions: [],
        )
        let seeds = ComposerScopeTreeNeighborhoodCandidates.make(
            editingPath: "/Users",
            selection: selection,
            favorites: [],
            backHistory: [],
            entryLoadingClient: .testValue,
        )

        XCTAssertFalse(seeds.contains { $0.path == "/" })
        XCTAssertEqual(seeds.first?.path, "/Users")
    }

    func testScopeTreeNeighborhoodCapsSiblingSeedsAfterFilteringExcludedPaths() {
        let selection = ComposerScopeSelection.explicit(
            bases: [
                ComposerScopeBase(path: "/Parent/Current"),
                ComposerScopeBase(path: "/Parent/Pinned"),
            ],
            exceptions: [
                ComposerScopeException(path: "/Parent/Excluded"),
            ],
        )
        let entryLoadingClient = makeMockEntryLoadingClient(
            siblingPaths: [
                "/Parent/A",
                "/Parent/Current",
                "/Parent/B",
                "/Parent/Pinned",
                "/Parent/C",
                "/Parent/Excluded",
                "/Parent/D",
            ],
        )

        let seeds = ComposerScopeTreeNeighborhoodCandidates.make(
            editingPath: "/Parent/Current",
            selection: selection,
            favorites: [],
            backHistory: [],
            entryLoadingClient: entryLoadingClient,
            maxSiblingCount: 2,
        )

        XCTAssertEqual(seeds.map(\.path), [
            "/Parent",
            "/Parent/Current",
            "/Parent/A",
            "/Parent/B",
        ])
    }

    private func makeComposerState(fixture: ChildFolderFixture) -> ComposerState {
        var state = ComposerState()
        state.scopeEditor.selection = fixture.selection
        state.scopeEditor.isPresented = true
        return state
    }

    private func makeScopeEditorState(
        fixture: ChildFolderFixture,
        candidateItems: [ComposerScopeEditorCandidateItem],
    ) -> ComposerScopeEditorState {
        ComposerScopeEditorState(
            selection: fixture.selection,
            listState: .childFolders(parentPath: fixture.editingURL.path),
            isPresented: true,
            queryText: "",
            editingPath: fixture.editingURL.path,
            entryMode: .edit,
            candidateItems: candidateItems,
            favorites: fixture.favorites,
            backHistory: fixture.backHistory,
        )
    }

    private func makeNeighborhoodSeeds(fixture: ChildFolderFixture) -> [ComposerScopeTreeSeedItem] {
        ComposerScopeTreeNeighborhoodCandidates.make(
            editingPath: fixture.editingURL.path,
            selection: fixture.selection,
            favorites: fixture.favorites,
            backHistory: fixture.backHistory,
            entryLoadingClient: fixture.entryLoadingClient,
        )
    }

    private func makeChildFolderFixture() throws -> ChildFolderFixture {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fixture = ChildFolderFixture(baseURL: temporaryRoot)

        try createFixtureDirectories(fixture)
        createFixtureFiles(fixture)

        return ChildFolderFixture(
            baseURL: temporaryRoot,
            selection: makeSelection(fixture),
            favorites: [ScopeFavoriteItem(name: "Favorite", url: fixture.siblingURL, iconName: "folder")],
            backHistory: [fixture.explicitBasePeerURL.path],
            entryLoadingClient: makeEntryLoadingClient(homeURL: temporaryRoot),
            expectedChildCandidates: makeExpectedChildCandidates(fixture),
        )
    }

    private func createFixtureDirectories(_ fixture: ChildFolderFixture) throws {
        for directory in [
            fixture.editingURL,
            fixture.siblingURL,
            fixture.explicitBasePeerURL,
            fixture.exceptionPeerURL,
            fixture.childArchiveURL,
            fixture.childReceiptsURL,
            fixture.workspaceCollectionURL,
            fixture.childCollectionURL,
        ] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func createFixtureFiles(_ fixture: ChildFolderFixture) {
        FileManager.default.createFile(atPath: fixture.workspaceFileURL.path, contents: Data())
        FileManager.default.createFile(atPath: fixture.childFileURL.path, contents: Data())
    }

    private func makeSelection(_ fixture: ChildFolderFixture) -> ComposerScopeSelection {
        .explicit(
            bases: [
                ComposerScopeBase(path: fixture.editingURL.path),
                ComposerScopeBase(path: fixture.explicitBasePeerURL.path),
            ],
            exceptions: [
                ComposerScopeException(path: fixture.exceptionPeerURL.path),
            ],
        )
    }

    private func makeExpectedChildCandidates(_ fixture: ChildFolderFixture) -> [ComposerScopeEditorCandidateItem] {
        [
            ComposerScopeEditorCandidateItem(
                path: fixture.childArchiveURL.path,
                name: "Archive",
                iconName: "folder",
                locationIdentifier: fixture.editingURL.path,
            ),
            ComposerScopeEditorCandidateItem(
                path: fixture.childReceiptsURL.path,
                name: "Receipts",
                iconName: "folder",
                locationIdentifier: fixture.editingURL.path,
            ),
        ]
    }

    private func makeEntryLoadingClient(homeURL: URL) -> EntryLoadingClient {
        var client = EntryLoadingClient.testValue
        client.contentsOfDirectory = { url, keys, options in
            try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: options,
            )
        }
        client.displayName = { ($0 as NSString).lastPathComponent }
        client.homeDirectory = { homeURL.path }
        client.fileExists = { FileManager.default.fileExists(atPath: $0) }
        return client
    }

    private func makeMockEntryLoadingClient(siblingPaths: [String]) -> EntryLoadingClient {
        var client = EntryLoadingClient.testValue
        client.contentsOfDirectory = { _, _, _ in
            siblingPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
        client.displayName = { ($0 as NSString).lastPathComponent }
        client.homeDirectory = { "/Users/test" }
        client.fileExists = { _ in true }
        return client
    }
}

private struct ChildFolderFixture {
    let temporaryRoot: URL
    let workspaceURL: URL
    let editingURL: URL
    let siblingURL: URL
    let explicitBasePeerURL: URL
    let exceptionPeerURL: URL
    let workspaceCollectionURL: URL
    let workspaceFileURL: URL
    let childArchiveURL: URL
    let childReceiptsURL: URL
    let childCollectionURL: URL
    let childFileURL: URL
    let selection: ComposerScopeSelection
    let favorites: [ScopeFavoriteItem]
    let backHistory: [String]
    let entryLoadingClient: EntryLoadingClient
    let expectedChildCandidates: [ComposerScopeEditorCandidateItem]

    init(
        baseURL: URL,
        selection: ComposerScopeSelection = .rootOnly,
        favorites: [ScopeFavoriteItem] = [],
        backHistory: [String] = [],
        entryLoadingClient: EntryLoadingClient = .testValue,
        expectedChildCandidates: [ComposerScopeEditorCandidateItem] = [],
    ) {
        temporaryRoot = baseURL
        workspaceURL = baseURL.appendingPathComponent("Workspace", isDirectory: true)
        editingURL = workspaceURL.appendingPathComponent("Current", isDirectory: true)
        siblingURL = workspaceURL.appendingPathComponent("Sibling", isDirectory: true)
        explicitBasePeerURL = workspaceURL.appendingPathComponent("Pinned", isDirectory: true)
        exceptionPeerURL = workspaceURL.appendingPathComponent("Excluded", isDirectory: true)
        workspaceCollectionURL = workspaceURL.appendingPathComponent("Workspace Search.voycoll", isDirectory: true)
        workspaceFileURL = workspaceURL.appendingPathComponent("note.txt", isDirectory: false)
        childArchiveURL = editingURL.appendingPathComponent("Archive", isDirectory: true)
        childReceiptsURL = editingURL.appendingPathComponent("Receipts", isDirectory: true)
        childCollectionURL = editingURL.appendingPathComponent("Saved Search.voycoll", isDirectory: true)
        childFileURL = editingURL.appendingPathComponent("draft.txt", isDirectory: false)
        self.selection = selection
        self.favorites = favorites
        self.backHistory = backHistory
        self.entryLoadingClient = entryLoadingClient
        self.expectedChildCandidates = expectedChildCandidates
    }
}
