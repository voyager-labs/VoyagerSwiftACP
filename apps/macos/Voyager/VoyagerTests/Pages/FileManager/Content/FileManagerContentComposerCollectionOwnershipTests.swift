import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
import VoyagerShared
import XCTest

@MainActor
final class FileManagerContentComposerCollectionOwnershipTests: XCTestCase {
    // MARK: - Search Success: Action Ordering

    func testSearchSuccessSendsSetCollectionModeBeforeApplyCollectionSearchPaths() async {
        let items: [JSONValue] = [
            .object(["fullPath": .string("/tmp/voyager/file1.txt")]),
            .object(["fullPath": .string("/tmp/voyager/file2.txt")]),
        ]

        var state = makeInitialState()
        state.composer.pendingSearchQuery = "test query"

        var receivedActions: [FileManagerContentAction] = []

        let effect = FileManagerContentComposerCoordinator.reduce(
            .internal(.filtersResponse(.success(SearchResponsePayload(
                itemCount: items.count, items: items,
            )))),
            state: &state,
            dependencies: .init(
                collectionAlertClient: .testValue,
                computerName: "TestMac",
            ),
        )

        for await action in effect.actions {
            receivedActions.append(action)
        }

        let setModeIndex = receivedActions.firstIndex {
            if case .entryViewLayout(.internal(.setCollectionMode(true))) = $0 { return true }
            return false
        }
        let applyPathsIndex = receivedActions.firstIndex {
            if case .entryViewLayout(.internal(.applyCollectionSearchPaths)) = $0 { return true }
            return false
        }

        XCTAssertNotNil(setModeIndex, "Expected setCollectionMode(true) action")
        XCTAssertNotNil(applyPathsIndex, "Expected applyCollectionSearchPaths action")
        if let setModeIndex, let applyPathsIndex {
            XCTAssertLessThan(setModeIndex, applyPathsIndex,
                              "setCollectionMode(true) must be sent before applyCollectionSearchPaths")
        }
    }

    // MARK: - Clear Collection Mode: Uses Layout Internal Action

    func testClearCollectionModeSendsClearCollectionPresentation() async {
        var state = makeInitialState()
        state.entryViewLayout.isCollectionMode = true
        state.collectionContext = CollectionContext(query: "test", scopes: [], conditions: [])

        var receivedActions: [FileManagerContentAction] = []
        let effect = clearCollectionMode(state: &state)

        for await action in effect.actions {
            receivedActions.append(action)
        }

        let hasClearPresentation = receivedActions.contains {
            if case .entryViewLayout(.internal(.clearCollectionPresentation)) = $0 { return true }
            return false
        }
        XCTAssertTrue(hasClearPresentation,
                      "clearCollectionMode must send entryViewLayout(.internal(.clearCollectionPresentation))")
    }

    // MARK: - State Reads: Uses Canonical Source

    func testSyncComposerCollectionStateReadsFromCanonicalSource() {
        var state = makeInitialState()
        state.entryViewLayout.isCollectionMode = true

        state.syncComposerCollectionState()

        XCTAssertTrue(state.composer.isCollectionMode,
                      "syncComposerCollectionState must read from entryViewLayout.isCollectionMode (canonical)")
    }

    func testCanSaveCollectionReadsFromCanonicalSource() {
        var state = makeInitialState()
        state.entryViewLayout.isCollectionMode = true
        state.collectionContext = CollectionContext(query: "test", scopes: [], conditions: [])

        XCTAssertTrue(state.canSaveCollection,
                      "canSaveCollection must read from entryViewLayout.isCollectionMode (canonical)")
    }

    // MARK: - Helpers

    private func makeInitialState() -> FileManagerContentState {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/tmp/voyager")
        return state
    }
}
