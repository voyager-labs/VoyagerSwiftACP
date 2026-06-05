import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared
import XCTest

/// 저장되지 않은 변경사항이 있을 때 내비게이션 동작 — 취소/폐기/저장을 검증.
@MainActor
final class FileManagerNavigationUnsavedTests: XCTestCase {
    /// testUnsavedPromptCancelDoesNotPerformNavigationForHistoryActions 테스트 동작을 검증한다.
    func testUnsavedPromptCancelDoesNotPerformNavigationForHistoryActions() async {
        for testCase in kHistoryNavigationTestCases {
            let store = makeStore(alertChoice: .cancel)

            await store.send(.navigation(.view(testCase.viewAction)))

            await store.receive {
                guard case let .navigation(.internal(.showUnsavedNavigationAlert(pending))) = $0 else { return false }
                return pendingMatches(pending, testCase.pending)
            }
            await store.receive {
                guard case let .navigation(.internal(.unsavedNavigationAlertResponse(pending, choice))) = $0 else {
                    return false
                }
                guard pendingMatches(pending, testCase.pending) else { return false }
                if case .cancel = choice {
                    return true
                }
                return false
            }

            XCTAssertNil(store.state.content.navigation.pendingNavigation)
            XCTAssertFalse(store.state.content.resetComposerOnNextDirectoryNavigation)

            await store.finish()
        }
    }

    /// testUnsavedPromptDiscardPerformsNavigationAndResetsComposerForHistoryActions 테스트 동작을 검증한다.
    func testUnsavedPromptDiscardPerformsNavigationAndResetsComposerForHistoryActions() async {
        for testCase in kHistoryNavigationTestCases {
            let store = makeStore(alertChoice: .discard, composerText: "dirty")

            await store.send(.navigation(.view(testCase.viewAction)))

            await store.receive {
                guard case let .navigation(.internal(.showUnsavedNavigationAlert(pending))) = $0 else { return false }
                return pendingMatches(pending, testCase.pending)
            }
            await store.receive {
                guard case let .navigation(.internal(.unsavedNavigationAlertResponse(pending, choice))) = $0 else {
                    return false
                }
                guard pendingMatches(pending, testCase.pending) else { return false }
                if case .discard = choice {
                    return true
                }
                return false
            } assert: { state in
                state.content.resetComposerOnNextDirectoryNavigation = true
            }
            await store.receive {
                guard case let .navigation(.internal(.performNavigation(pending))) = $0 else { return false }
                return pendingMatches(pending, testCase.pending)
            }
            await store.skipReceivedActions()

            XCTAssertNil(store.state.content.navigation.pendingNavigation)
            XCTAssertFalse(store.state.content.resetComposerOnNextDirectoryNavigation)
            XCTAssertEqual(store.state.content.composer.text, "")

            await store.finish()
        }
    }

    /// testUnsavedPromptSaveSetsPendingNavigationAndStartsSaveForHistoryActions 테스트 동작을 검증한다.
    func testUnsavedPromptSaveSetsPendingNavigationAndStartsSaveForHistoryActions() async {
        for testCase in kHistoryNavigationTestCases {
            let store = makeStore(alertChoice: .save)

            await store.send(.navigation(.view(testCase.viewAction)))

            await store.receive {
                guard case let .navigation(.internal(.showUnsavedNavigationAlert(pending))) = $0 else { return false }
                return pendingMatches(pending, testCase.pending)
            }
            await store.receive {
                guard case let .navigation(.internal(.unsavedNavigationAlertResponse(pending, choice))) = $0 else {
                    return false
                }
                guard pendingMatches(pending, testCase.pending) else { return false }
                if case .save = choice {
                    return true
                }
                return false
            } assert: { state in
                state.content.resetComposerOnNextDirectoryNavigation = true
            }
            await store.receive {
                guard case let .navigation(.internal(.setPendingNavigation(pending))) = $0 else { return false }
                return optionalPendingMatches(pending, testCase.pending)
            } assert: { state in
                state.content.navigation.pendingNavigation = testCase.pending
            }
            await store.receive {
                guard case .content(.composer(.view(.saveCollection))) = $0 else { return false }
                return true
            }

            XCTAssertTrue(optionalPendingMatches(store.state.content.navigation.pendingNavigation, testCase.pending))
            XCTAssertTrue(store.state.content.resetComposerOnNextDirectoryNavigation)

            await store.finish()
        }
    }
}

private struct HistoryNavigationTestCase {
    let viewAction: ContentPageNavigationAction.View
    let pending: ContentPageNavigationPending
}

private func pendingMatches(
    _ lhs: ContentPageNavigationPending,
    _ rhs: ContentPageNavigationPending,
) -> Bool {
    switch (lhs, rhs) {
    case (.back, .back),
         (.forward, .forward),
         (.enclosingDirectory, .enclosingDirectory):
        true

    case let (.history(index: lhsIndex, isBackHistory: lhsIsBack), .history(index: rhsIndex, isBackHistory: rhsIsBack)):
        lhsIndex == rhsIndex && lhsIsBack == rhsIsBack

    default:
        false
    }
}

private func optionalPendingMatches(
    _ lhs: ContentPageNavigationPending?,
    _ rhs: ContentPageNavigationPending,
) -> Bool {
    guard let lhs else { return false }
    return pendingMatches(lhs, rhs)
}

private let kHistoryNavigationTestCases: [HistoryNavigationTestCase] = [
    HistoryNavigationTestCase(viewAction: .goBack, pending: .back),
    HistoryNavigationTestCase(viewAction: .goForward, pending: .forward),
    HistoryNavigationTestCase(
        viewAction: .goToHistoryIndex(3, isBackHistory: true),
        pending: .history(index: 3, isBackHistory: true),
    ),
    HistoryNavigationTestCase(viewAction: .goToEnclosingDirectory, pending: .enclosingDirectory),
]

@MainActor
private func makeStore(
    alertChoice: CollectionNavigationChoice,
    composerText: String = "",
) -> TestStore<FileManagerWindowState, FileManagerWindowAction> {
    let collectionURL = URL(fileURLWithPath: "/tmp/test.voycoll")

    var state = FileManagerWindowState()
    state.content.entryViewLayout.isCollectionMode = true
    state.content.collection.collectionContext = CollectionContext(query: "Query", scopes: ["/tmp"], conditions: [])
    state.content.collection.collectionSession.document = .init(
        url: collectionURL,
        name: collectionURL.deletingPathExtension().lastPathComponent,
        compatibility: nil,
    )
    state.content.syncComposerCollectionState()
    state.content.composer.text = composerText

    let store = TestStore(initialState: state) {
        WindowNavUnsavedHarness()
    } withDependencies: {
        $0.collectionAlertClient = CollectionAlertClient(
            showUnsavedNavigationAlert: { alertChoice },
            showCollectionOpenErrorAlert: { _, _ in },
        )
        $0.collectionFileClient = .testValue
        $0.registryClient = .testValue
        $0.userDefaultsClient = .testValue
        $0.fileManagerClient = .testValue
        $0.thumbnailGeneratorClient = .testValue
        $0.entryThumbnailCacheClient = .testValue
        $0.notificationCenterClient = .testValue
        $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
    }

    store.exhaustivity = .off

    return store
}

@MainActor
@Reducer
private struct WindowNavUnsavedHarness {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Scope(state: \.content.navigation, action: \.navigation) {
            ContentPageNavigationFeature()
        }
        Scope(state: \.content, action: \.content) {
            FileManagerContentFeature()
        }
        FileManagerWindowNavigationReducer()
    }
}
