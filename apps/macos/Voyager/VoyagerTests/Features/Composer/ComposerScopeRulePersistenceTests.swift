import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerShared
import XCTest

@MainActor
final class ComposerScopeRulePersistenceTests: XCTestCase {
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
        XCTAssertFalse(store.state.scopeEditor.hasExceptions)
        XCTAssertFalse(store.state.scopeEditor.includeSubfolders)
        XCTAssertFalse(
            store.state.scopeEditor.sections()
                .flatMap(\.items)
                .contains { if case .exceptionScope = $0 { true } else { false } },
        )
    }
}
