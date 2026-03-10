import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class FileManagerContentComposerStabilityTests: XCTestCase {
    func testSaveCompletedAppendsPreviousCollectionSnapshotDeterministically() async {
        let oldURL = URL(fileURLWithPath: "/tmp/old.voycoll")
        let newURL = URL(fileURLWithPath: "/tmp/new.voycoll")
        let oldContext = CollectionContext(query: "old", scopes: ["/tmp"], conditions: [])

        var state = FileManagerContentState()
        state.collectionContext = CollectionContext(query: "new", scopes: ["/tmp/new"], conditions: [])
        state.collectionSession.openedURL = oldURL
        state.collectionSession.openedName = "Old"
        state.collectionSession.baseline = CollectionBaseline(context: oldContext)
        state.navigation.seedInitialFolderPath("/seed")

        let store = makeContentComposerStore(initialState: state)

        await store.send(.composer(.collection(.saveCompleted(.success(newURL)))))

        await store.receive {
            guard case .requestNavigation(.internal(.setNavigationState(.collection))) = $0 else {
                return false
            }
            return true
        }
        await store.receive {
            guard case let .requestNavigation(.internal(.appendBackHistory(entry))) = $0 else {
                return false
            }
            guard case let .collection(navigation) = entry.navigationState else { return false }
            guard case let .file(url, name) = navigation.kind else { return false }
            return url == oldURL && name == "Old" && navigation.context == oldContext
        }
        await store.receive {
            guard case .requestNavigation(.internal(.clearForwardHistory)) = $0 else {
                return false
            }
            return true
        }
        XCTAssertEqual(store.state.navigation.backHistory.count, 1)
    }

    func testSaveCompletedClearsPendingNavigationThenPerformsIt() async {
        let oldURL = URL(fileURLWithPath: "/tmp/old.voycoll")
        let newURL = URL(fileURLWithPath: "/tmp/new.voycoll")

        var state = FileManagerContentState()
        state.collectionContext = CollectionContext(query: "new", scopes: ["/tmp/new"], conditions: [])
        state.collectionSession.openedURL = oldURL
        state.collectionSession.openedName = "Old"
        state.collectionSession.baseline = CollectionBaseline(context: .init(
            query: "old",
            scopes: ["/tmp"],
            conditions: [],
        ))
        state.navigation.pendingNavigation = .back

        let store = makeContentComposerStore(initialState: state)

        await store.send(.composer(.collection(.saveCompleted(.success(newURL)))))
        await assertSaveSuccessNavigationSequence(store: store, expectPendingNavigation: .back)
    }
}

@MainActor
@Reducer
private struct ContentComposerHarness {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    var body: some Reducer<State, Action> {
        Scope(state: \.navigation, action: \.requestNavigation) {
            ContentPageNavigationStateReducer()
        }
        FileManagerContentComposerFeature()
    }
}

@MainActor
private func makeContentComposerStore(
    initialState: FileManagerContentState,
) -> TestStore<FileManagerContentState, FileManagerContentAction> {
    let store = TestStore(initialState: initialState) {
        ContentComposerHarness()
    } withDependencies: {
        $0.fileManagerComputerNameClient = .testValue
        $0.collectionAlertClient = .testValue
    }
    store.exhaustivity = .off
    return store
}

@MainActor
private func assertSaveSuccessNavigationSequence(
    store: TestStore<FileManagerContentState, FileManagerContentAction>,
    expectPendingNavigation: ContentPageNavigationPending,
) async {
    await store.receive {
        guard case .requestNavigation(.internal(.setNavigationState(.collection))) = $0 else {
            return false
        }
        return true
    }
    await store.receive {
        guard case .requestNavigation(.internal(.appendBackHistory)) = $0 else {
            return false
        }
        return true
    }
    await store.receive {
        guard case .requestNavigation(.internal(.clearForwardHistory)) = $0 else {
            return false
        }
        return true
    }
    await store.receive {
        guard case .requestNavigation(.internal(.setPendingNavigation(nil))) = $0 else {
            return false
        }
        return true
    } assert: {
        $0.navigation.pendingNavigation = nil
    }
    await store.receive {
        guard case let .performPendingNavigation(pending) = $0 else {
            return false
        }
        return pending == expectPendingNavigation
    }
}
