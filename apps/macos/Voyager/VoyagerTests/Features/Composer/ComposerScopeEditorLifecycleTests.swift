import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import XCTest

@MainActor
final class ComposerScopeEditorLifecycleTests: XCTestCase {
    func testScopeEditorOpenSeedsPresentationState() async {
        let store = TestStore(initialState: ComposerState()) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }

        await store.send(
            .scopeEditorOpen(editingPath: "/Users/test/Documents", favorites: [], backHistory: []),
        ) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = "/Users/test/Documents"
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
            $0.scopeEditor.favorites = []
            $0.scopeEditor.backHistory = []
        }

        await store.finish()
    }

    func testScopeEditorQueryThenDismissClearsInteractionState() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }

        await store.send(.scopeEditorSetQueryText("docs")) {
            $0.scopeEditor.queryText = "docs"
            $0.scopeEditor.listState = .searchResults(query: "docs")
            $0.scopeEditor.candidateItems = []
        }

        await store.send(.scopeEditorSetPresented(false)) {
            $0.scopeEditor.isPresented = false
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.editingPath = nil
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        await store.finish()
    }

    func testScopeEditorRetappingEditingTargetReturnsToAddMode() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.editingPath = "/Users/test/Documents"
        initialState.scopeEditor.entryMode = .edit
        initialState.scopeEditor.queryText = "docs"
        initialState.scopeEditor.listState = .searchResults(query: "docs")

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }

        await store.send(.scopeEditorOpen(editingPath: nil, favorites: [], backHistory: [])) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = nil
            $0.scopeEditor.entryMode = .add
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        await store.finish()
    }

    func testScopeEditorAddKeepsPopoverOpen() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }

        await store.send(.addScope(path: "/Users/test/Documents")) {
            $0.scopeEditor.selection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/test/Documents")],
                exceptions: [],
            )
            $0.scopes = ["/Users/test/Documents"]
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = nil
            $0.scopeEditor.entryMode = .add
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        await store.finish()
    }

    func testScopeEditorRemoveKeepsPopoverOpenAndEditMode() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.selection = .explicit(
            bases: [
                ComposerScopeBase(path: "/Users/test/Documents"),
                ComposerScopeBase(path: "/Users/test/Downloads"),
            ],
            exceptions: [],
        )
        initialState.scopeEditor.editingPath = "/Users/test/Documents"
        initialState.scopeEditor.entryMode = .edit
        initialState.scopes = ["/Users/test/Documents", "/Users/test/Downloads"]

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }

        await store.send(.removeScope(path: "/Users/test/Downloads")) {
            $0.scopeEditor.selection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/test/Documents")],
                exceptions: [],
            )
            $0.scopes = ["/Users/test/Documents"]
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = "/Users/test/Documents"
            $0.scopeEditor.entryMode = .edit
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        await store.finish()
    }

    func testScopeEditorReplaceContinuesEditingTargetWithNewPath() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/test/Documents")],
            exceptions: [],
        )
        initialState.scopeEditor.editingPath = "/Users/test/Documents"
        initialState.scopeEditor.entryMode = .edit
        initialState.scopes = ["/Users/test/Documents"]

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }

        await store.send(.updateScope(oldPath: "/Users/test/Documents", newPath: "/Users/test/Desktop")) {
            $0.scopeEditor.selection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/test/Desktop")],
                exceptions: [],
            )
            $0.scopes = ["/Users/test/Desktop"]
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = "/Users/test/Desktop"
            $0.scopeEditor.entryMode = .edit
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        await store.finish()
    }

    func testScopeEditorSearchResponseIgnoresStaleQuery() async {
        var initialState = ComposerState()
        initialState.scopeEditor.queryText = "docs"
        initialState.scopeEditor.listState = .searchResults(query: "docs")

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }

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
}
