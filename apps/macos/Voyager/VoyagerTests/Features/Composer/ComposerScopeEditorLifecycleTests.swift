import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerShared
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

    func testScopeEditorOpenSeedsCommittedBaselineFromCollectionContext() async {
        var initialState = ComposerState()
        initialState.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/test/Temporary")],
            exceptions: [],
        )
        initialState.scopeEditor.includeSubfolders = false
        initialState.collectionContext = CollectionContext(
            query: "kind:image",
            scopes: ["/Users/test/Documents"],
            includeSubfolders: true,
            conditions: [],
        )

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }

        await store.send(
            .scopeEditorOpen(editingPath: nil, favorites: [], backHistory: []),
        ) {
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.editingPath = nil
            $0.scopeEditor.entryMode = .add
            $0.scopeEditor.selection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/test/Documents")],
                exceptions: [],
            )
            $0.scopeEditor.includeSubfolders = true
            $0.scopeEditor.committedSelection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/test/Documents")],
                exceptions: [],
            )
            $0.scopeEditor.committedIncludeSubfolders = true
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

    func testScopeEditorDismissDoesNotReapplyFiltersForIncompleteCondition() async {
        let applyRecorder = ScopeEditorApplyFiltersRecorder()

        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/test/Documents")],
            exceptions: [],
        )
        initialState.scopes = ["/Users/test/Documents"]
        initialState.conditions = [
            Condition(
                propertyKey: "name",
                propertyLabel: "Name",
                propertyType: "string",
                operatorCode: nil,
                operatorLabel: nil,
                operatorValueArity: nil,
                operatorValueUIKind: nil,
                valueType: "string",
                values: nil,
                isActive: true,
            ),
        ]
        initialState.collectionContext = CollectionContext(
            query: "draft",
            scopes: ["/Users/test/Documents"],
            includeSubfolders: true,
            conditions: initialState.conditions,
        )
        initialState.scopeEditor.includeSubfolders = false

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient.applyFilters = { request in
                await applyRecorder.record(request)
                return VoyagerShared.SearchResponsePayload(itemCount: 0)
            }
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }

        await store.send(.scopeEditorSetPresented(false)) {
            $0.scopeEditor.isPresented = false
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.editingPath = nil
            $0.scopeEditor.entryMode = .add
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        let lastApplyRequest = await applyRecorder.last()
        XCTAssertNil(lastApplyRequest)
        await store.finish()
    }

    func testScopeEditorAddDoesNotReapplyFiltersForIncompleteCondition() async {
        let applyRecorder = ScopeEditorApplyFiltersRecorder()

        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true
        initialState.conditions = [
            Condition(
                propertyKey: "name",
                propertyLabel: "Name",
                propertyType: "string",
                operatorCode: nil,
                operatorLabel: nil,
                operatorValueArity: nil,
                operatorValueUIKind: nil,
                valueType: "string",
                values: nil,
                isActive: true,
            ),
        ]

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient.applyFilters = { request in
                await applyRecorder.record(request)
                return VoyagerShared.SearchResponsePayload(itemCount: 0)
            }
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

        let lastApplyRequest = await applyRecorder.last()
        XCTAssertNil(lastApplyRequest)
        await store.finish()
    }
}

private actor ScopeEditorApplyFiltersRecorder {
    private var requests: [VoyagerShared.FiltersOnlyRequestPayload] = []

    func record(_ request: VoyagerShared.FiltersOnlyRequestPayload) {
        requests.append(request)
    }

    func last() -> VoyagerShared.FiltersOnlyRequestPayload? {
        requests.last
    }
}
