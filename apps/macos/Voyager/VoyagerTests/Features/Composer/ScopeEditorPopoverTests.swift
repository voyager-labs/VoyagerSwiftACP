import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesEntry
import XCTest

@MainActor
final class ScopeEditorPopoverTests: XCTestCase {
    func testBottomRowScopeRemoveKeepsPopoverClosed() async {
        var initialState = ComposerState()
        initialState.scopeEditor.isPresented = false
        initialState.scopeEditor.selection = .explicit(
            bases: [
                ComposerScopeBase(path: "/Users/test/Documents"),
                ComposerScopeBase(path: "/Users/test/Downloads"),
            ],
            exceptions: [],
        )
        initialState.scopes = ["/Users/test/Documents", "/Users/test/Downloads"]

        let store = makePassiveStore(initialState: initialState)

        await store.send(.removeScope(path: "/Users/test/Downloads")) {
            $0.scopeEditor.selection = .explicit(
                bases: [ComposerScopeBase(path: "/Users/test/Documents")],
                exceptions: [],
            )
            $0.scopes = ["/Users/test/Documents"]
            $0.scopeEditor.isPresented = false
            $0.scopeEditor.editingPath = nil
            $0.scopeEditor.entryMode = .add
        }

        await store.finish()
    }
}

@MainActor
private func makePassiveStore(initialState: ComposerState) -> TestStore<ComposerState, ComposerAction> {
    TestStore(initialState: initialState) {
        ComposerFeature()
    } withDependencies: {
        $0.searchClient = .testValue
        $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = .testValue
    }
}
