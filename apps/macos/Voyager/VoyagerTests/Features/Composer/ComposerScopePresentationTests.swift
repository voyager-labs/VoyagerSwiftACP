import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerShared
import XCTest

@MainActor
final class ComposerScopePresentationTests: XCTestCase {
    func testCollectionContextIncludesExcludedScopes() {
        var state = ComposerState()
        state.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/me/Documents")],
            exceptions: [ComposerScopeException(path: "/Users/me/Documents/Secret")],
        )
        state.scopeEditor.includeSubfolders = true

        let context = state.collectionContext(query: "docs")

        XCTAssertEqual(context.scopes, ["/Users/me/Documents"])
        XCTAssertEqual(context.excludedScopes, ["/Users/me/Documents/Secret"])
        XCTAssertTrue(context.includeSubfolders)
    }

    func testCollectionRestorePayloadsPreserveExcludedScopes() {
        let context = CollectionContext(
            query: "docs",
            scopes: ["/Users/me/Documents"],
            excludedScopes: ["/Users/me/Documents/Secret"],
            includeSubfolders: true,
            conditions: [],
        )

        var draftState = ComposerState()
        draftState.applyCollectionDraftRestorePayload(.init(context: context, openedURL: nil))
        XCTAssertEqual(draftState.scopeEditor.selection.explicitBases.map(\.path), ["/Users/me/Documents"])
        XCTAssertEqual(draftState.scopeEditor.selection.exceptions.map(\.path), ["/Users/me/Documents/Secret"])

        var navigationState = ComposerState()
        navigationState.applyCollectionNavigationComposerPayload(.init(
            context: context,
            includeSubfolders: true,
            document: nil,
            baseline: nil,
            composerText: "docs",
            scopes: ["/Users/me/Documents"],
            excludedScopes: ["/Users/me/Documents/Secret"],
            conditions: [],
        ))
        XCTAssertEqual(navigationState.scopeEditor.selection.explicitBases.map(\.path), ["/Users/me/Documents"])
        XCTAssertEqual(navigationState.scopeEditor.selection.exceptions.map(\.path), ["/Users/me/Documents/Secret"])

        var openState = ComposerState()
        openState.applyCollectionOpenRestorationComposerPayload(
            .init(
                context: context,
                compatibility: nil,
                navigation: nil,
                shouldRestoreStaleNavigation: false,
                queryTrigger: nil,
                hydratedOpenPayload: nil,
                isEmptyDefinition: false,
                unsupportedFilterKeys: [],
            ),
            registryClient: .testValue,
        )
        XCTAssertEqual(openState.scopeEditor.selection.explicitBases.map(\.path), ["/Users/me/Documents"])
        XCTAssertEqual(openState.scopeEditor.selection.exceptions.map(\.path), ["/Users/me/Documents/Secret"])
        XCTAssertEqual(openState.lastFiltersResponse?.appliedFilters?.excludedScopes, ["/Users/me/Documents/Secret"])
    }

    func testScopeEditorOpenSeedsCommittedExcludedScopesFromCollectionContext() async {
        var initialState = ComposerState()
        initialState.collectionContext = CollectionContext(
            query: "docs",
            scopes: ["/Users/me/Documents"],
            excludedScopes: ["/Users/me/Documents/Secret"],
            includeSubfolders: true,
            conditions: [],
        )

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }

        await store.send(.scopeEditorOpen(editingPath: nil, favorites: [], backHistory: [])) {
            $0.scopeEditor.selection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [ComposerScopeException(path: "/Users/me/Documents/Secret")],
            )
            $0.scopeEditor.includeSubfolders = true
            $0.scopeEditor.committedSelection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [ComposerScopeException(path: "/Users/me/Documents/Secret")],
            )
            $0.scopeEditor.committedIncludeSubfolders = true
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
            $0.scopeEditor.favorites = []
            $0.scopeEditor.backHistory = []
        }
    }

    func testScopeRuleDefaultsToIncludeSubfoldersAndProvidesDescriptions() {
        let rootState = ComposerState()
        XCTAssertTrue(rootState.scopeEditor.effectiveIncludeSubfolders)
        XCTAssertEqual(rootState.scopeEditor.scopeRuleDescription, "This Mac")
        XCTAssertFalse(rootState.scopeEditor.isExactFolderOnlyMode)

        var toggledRootState = ComposerState()
        toggledRootState.scopeEditor.includeSubfolders = false

        XCTAssertTrue(toggledRootState.scopeEditor.effectiveIncludeSubfolders)
        XCTAssertEqual(toggledRootState.scopeEditor.scopeRuleDescription, "This Mac")
        XCTAssertFalse(toggledRootState.scopeEditor.isExactFolderOnlyMode)
        XCTAssertTrue(toggledRootState.collectionContext(query: "docs").includeSubfolders)
        XCTAssertTrue(buildFilters(from: toggledRootState).includeSubfolders)

        var explicitState = ComposerState()
        explicitState.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/me/Documents")],
            exceptions: [],
        )
        explicitState.scopeEditor.includeSubfolders = false

        XCTAssertFalse(explicitState.scopeEditor.effectiveIncludeSubfolders)
        XCTAssertTrue(explicitState.scopeEditor.isExactFolderOnlyMode)
        XCTAssertEqual(explicitState.scopeEditor.scopeRuleDescription, "Only selected folder")
        XCTAssertFalse(explicitState.collectionContext(query: "docs").includeSubfolders)
        XCTAssertFalse(buildFilters(from: explicitState).includeSubfolders)
    }

    func testScopeEditorIncludeSubfoldersToggleUpdatesContext() {
        var state = ComposerState()
        state.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/me/Documents")],
            exceptions: [],
        )

        state.scopeEditor.includeSubfolders = false
        XCTAssertFalse(state.scopeEditor.effectiveIncludeSubfolders)
        XCTAssertTrue(state.scopeEditor.isExactFolderOnlyMode)
        XCTAssertEqual(state.scopeEditor.scopeRuleDescription, "Only selected folder")
        XCTAssertFalse(state.collectionContext(query: "docs").includeSubfolders)

        state.scopeEditor.includeSubfolders = true
        XCTAssertTrue(state.scopeEditor.effectiveIncludeSubfolders)
        XCTAssertFalse(state.scopeEditor.isExactFolderOnlyMode)
        XCTAssertEqual(state.scopeEditor.scopeRuleDescription, "Include subfolders")
        XCTAssertTrue(state.collectionContext(query: "docs").includeSubfolders)
    }

    func testScopeSummaryReflectsRootSingleAndMultiSelection() {
        XCTAssertEqual(ComposerScopeSelection.rootOnly.summary.primaryText, "This Mac")

        let single = ComposerScopeSelection.explicit(
            bases: [ComposerScopeBase(path: "/Users/me/Documents")],
            exceptions: [],
        )
        XCTAssertEqual(single.summary.primaryText, "/Users/me/Documents")
        XCTAssertNil(single.summary.secondaryText)

        let multi = ComposerScopeSelection.explicit(
            bases: [
                ComposerScopeBase(path: "/Users/me/Documents"),
                ComposerScopeBase(path: "/Users/me/Downloads"),
            ],
            exceptions: [ComposerScopeException(path: "/Users/me/Documents/Secrets")],
        )
        XCTAssertEqual(multi.summary.primaryText, "2 Scopes")
        XCTAssertEqual(multi.summary.secondaryText, "1 exception")
    }

    func testScopeAddPreservesNestedExplicitScopesAndSkipsAutoApplyWithoutConditions() async {
        let initialSelection = ComposerScopeSelection.explicit(
            bases: [ComposerScopeBase(path: "/Users/me")],
            exceptions: [],
        )
        var initialState = ComposerState()
        initialState.scopeEditor.selection = initialSelection
        initialState.scopeEditor.isPresented = true

        let applyRecorder = ScopeApplyFiltersRecorder()
        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient.applyFilters = { request in
                applyRecorder.record(request)
                return VoyagerShared.SearchResponsePayload(
                    itemCount: 0,
                    appliedFilters: request.filters.asAppliedFiltersPayload,
                    items: nil,
                    error: nil,
                )
            }
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }
        store.exhaustivity = .off

        await store.send(.candidateScope(.add(path: "/Users/me/Documents"))) {
            $0.scopeEditor.selection = .explicit(
                bases: [
                    ComposerScopeBase(path: "/Users/me"),
                    ComposerScopeBase(path: "/Users/me/Documents"),
                ],
                exceptions: [],
            )
            $0.scopes = ["/Users/me", "/Users/me/Documents"]
            $0.scopeEditor.isPresented = true
            $0.scopeEditor.queryText = ""
            $0.scopeEditor.listState = .defaultCandidates
            $0.scopeEditor.candidateItems = []
        }

        XCTAssertNil(applyRecorder.last())
    }

    func testScopeEditorSeedCurrentPathRootFoldsAndNormalizes() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = true

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }

        await store.send(.internal(.scopeEditorSeedCurrentPath("/"))) {
            $0.scopeEditor.selection = .rootOnly
            $0.scopes = ["/"]
        }

        var normalizedState = ComposerState()
        normalizedState.scopeEditor.isPresented = true

        let normalizedStore = TestStore(initialState: normalizedState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }

        await normalizedStore.send(.internal(.scopeEditorSeedCurrentPath("/Users/me/Documents/"))) {
            $0.scopeEditor.selection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/me/Documents")],
                exceptions: [],
            )
            $0.scopes = ["/Users/me/Documents"]
        }
    }

    func testApplyAppliedFiltersPreservesLocalMultiScopeWhenBackendCollapsesSelection() {
        var state = ComposerState()
        state.scopeEditor.selection = .explicit(
            bases: [
                ComposerScopeBase(path: "/Users/me/Documents"),
                ComposerScopeBase(path: "/Users/me/Downloads"),
            ],
            exceptions: [],
        )
        state.scopes = state.scopeEditor.selection.legacyScopePaths

        applyAppliedFilters(
            .init(scopes: ["/Users/me/Documents"], conditions: []),
            state: &state,
            registryClient: .testValue,
        )

        XCTAssertEqual(state.scopeEditor.selection.legacyScopePaths, ["/Users/me/Documents", "/Users/me/Downloads"])
    }
}

private final class ScopeApplyFiltersRecorder: @unchecked Sendable {
    private var requests: [VoyagerShared.FiltersOnlyRequestPayload] = []

    func record(_ request: VoyagerShared.FiltersOnlyRequestPayload) {
        requests.append(request)
    }

    func last() -> VoyagerShared.FiltersOnlyRequestPayload? {
        requests.last
    }
}

private extension VoyagerShared.SearchFiltersPayload {
    var asAppliedFiltersPayload: VoyagerShared.AppliedFiltersPayload {
        VoyagerShared.AppliedFiltersPayload(scopes: scopes, conditions: conditions)
    }

    func testUndoRedoPreservesExcludedScopes() async {
        let baseSelection = ComposerScopeSelection.explicit(
            bases: [ComposerScopeBase(path: "/Users/me/Documents")],
            exceptions: [],
        )
        let excludedSelection = ComposerScopeSelection.explicit(
            bases: [ComposerScopeBase(path: "/Users/me/Documents")],
            exceptions: [ComposerScopeException(path: "/Users/me/Documents/Secret")],
        )

        var initialState = ComposerState()
        initialState.scopeEditor.selection = baseSelection
        initialState.history = [
            FilterSnapshot(
                scopeSelection: excludedSelection,
                conditions: [],
                conditionDisplayByKey: [:],
            ),
        ]

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient = .testValue
            $0.registryClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }
        store.exhaustivity = .off

        await store.send(.undo)
        XCTAssertEqual(store.state.scopeEditor.selection.exceptions.map(\.path), ["/Users/me/Documents/Secret"])

        await store.send(.redo)
        XCTAssertEqual(store.state.scopeEditor.selection.exceptions.map(\.path), [])
    }

    func testIncludeSubfoldersTogglePrunesExceptionsInExactFolderMode() async {
        var initialState = ComposerState()
        initialState.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/Users/me/Documents")],
            exceptions: [ComposerScopeException(path: "/Users/me/Documents/Secret")],
        )
        initialState.scopeEditor.includeSubfolders = true

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }
        store.exhaustivity = .off

        await store.send(.scopeEditorSetIncludeSubfolders(false))

        XCTAssertEqual(store.state.scopeEditor.selection.explicitBases.map(\.path), ["/Users/me/Documents"])
        XCTAssertEqual(store.state.scopeEditor.selection.exceptions.map(\.path), [])
        XCTAssertFalse(store.state.scopeEditor.includeSubfolders)
    }
}
