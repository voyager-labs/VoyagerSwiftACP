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

        let store = TestStore(initialState: makeState(parentURL: fixture.parentURL)) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = fixture.entryLoadingClient
        }

        await store.send(.scopeEditorOpen(editingPath: fixture.parentURL.path, favorites: [], backHistory: [])) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = fixture.parentURL.path
            $0.scopeEditor.entryMode = .edit
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.listState = .childFolders(parentPath: fixture.parentURL.path)
            $0.scopeEditor.candidateItems = fixture.expectedCandidates
            $0.scopeEditor.favorites = []
            $0.scopeEditor.backHistory = []
        }

        XCTAssertFalse(store.state.scopeEditor.candidateItems.contains { $0.path == fixture.collectionURL.path })
        XCTAssertEqual(
            store.state.scopeEditor.candidateSelectionIntent(for: fixture.receiptsURL.path),
            .exclude(path: fixture.receiptsURL.path),
        )
        await store.finish()
    }

    private func makeState(parentURL: URL) -> ComposerState {
        var state = ComposerState()
        state.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: parentURL.path)],
            exceptions: [],
        )
        state.scopeEditor.isPresented = true
        return state
    }

    private func makeChildFolderFixture() throws -> ChildFolderFixture {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let parentURL = temporaryRoot.appendingPathComponent("Parent", isDirectory: true)
        let archiveURL = parentURL.appendingPathComponent("Archive", isDirectory: true)
        let receiptsURL = parentURL.appendingPathComponent("Receipts", isDirectory: true)
        let collectionURL = parentURL.appendingPathComponent("Saved Search.voycoll", isDirectory: true)
        let fileURL = parentURL.appendingPathComponent("note.txt", isDirectory: false)

        try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: receiptsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: collectionURL, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())

        return ChildFolderFixture(
            temporaryRoot: temporaryRoot,
            parentURL: parentURL,
            receiptsURL: receiptsURL,
            collectionURL: collectionURL,
            entryLoadingClient: makeEntryLoadingClient(homeURL: temporaryRoot),
            expectedCandidates: [
                ComposerScopeEditorCandidateItem(path: archiveURL.path, name: "Archive", iconName: "folder"),
                ComposerScopeEditorCandidateItem(path: receiptsURL.path, name: "Receipts", iconName: "folder"),
            ],
        )
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
        return client
    }
}

private struct ChildFolderFixture {
    let temporaryRoot: URL
    let parentURL: URL
    let receiptsURL: URL
    let collectionURL: URL
    let entryLoadingClient: EntryLoadingClient
    let expectedCandidates: [ComposerScopeEditorCandidateItem]
}
