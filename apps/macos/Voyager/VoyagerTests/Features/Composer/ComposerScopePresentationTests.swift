import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerShared
import XCTest

@MainActor
final class ComposerScopePresentationTests: XCTestCase {
    func testScopeRuleDefaultsToIncludeSubfoldersAndProvidesDescriptions() {
        let rootState = ComposerState()
        XCTAssertTrue(rootState.scopeEditor.effectiveIncludeSubfolders)
        XCTAssertEqual(rootState.scopeEditor.scopeRuleDescription, "This Mac")
        XCTAssertFalse(rootState.scopeEditor.isExactFolderOnlyMode)

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

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
        }

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

        await store.finish()
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
