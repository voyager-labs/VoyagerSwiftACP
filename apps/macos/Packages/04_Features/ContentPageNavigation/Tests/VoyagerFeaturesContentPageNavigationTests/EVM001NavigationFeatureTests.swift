import ComposableArchitecture
import VoyagerEntitiesCollection
@testable import VoyagerFeaturesContentPageNavigation
import VoyagerShared
import XCTest

@MainActor
final class EVM001NavigationFeatureTests: XCTestCase {
    // MARK: - EVM-001-navigate_pages

    /// 동일 경로로 navigate하면 history를 기록하지 않지만
    /// resetComposer 없이 logDAU + navigateToState 델리게이트는 발생한다.
    func testDirectNavigateToSamePathDoesNotRecordHistory() async {
        let store = makeStore(seedPath: "/seed")

        await store.send(.internal(.performNavigateToPath("/seed")))

        await store.receive(.delegate(.logDAUNavigation(
            previous: .folder("/seed"),
            next: .folder("/seed"),
        )))
        await store.receive(.delegate(.navigateToState(.folder("/seed"))))
    }

    /// 다른 경로로 navigate하면 backHistory에 스냅샷이 기록되고
    /// forwardHistory가 초기화되며 델리게이트 순서는 resetComposer → logDAU → navigateToState이다.
    func testDirectNavigateRecordsHistoryAndEmitsDelegates() async {
        let store = makeStore(seedPath: "/seed")

        await store.send(.internal(.performNavigateToPath("/next"))) {
            $0.navigationState = .folder("/next")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/seed"))]
            $0.forwardHistory = []
        }

        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/seed"), next: .folder("/next"))))
        await store.receive(.delegate(.navigateToState(.folder("/next"))))
    }

    // MARK: - EVM-001-go_page_history_back

    /// backHistory가 비어있을 때 back 네비게이션은 no-op이다.
    func testBackOnEmptyHistoryIsNoop() async {
        let store = makeStore(seedPath: "/seed")

        await store.send(.internal(.performNavigation(.back)))
    }

    /// back 네비게이션: 현재 상태를 forwardHistory로 이동, backHistory 마지막을 복원.
    /// 델리게이트 순서: resetComposer → logDAU → navigateToState
    func testBackMovesCurrentToForwardAndRestoresPrevious() async {
        let store = makeStore(seedPath: "/seed")

        // 먼저 /next로 이동하여 backHistory를 채운다
        await store.send(.internal(.performNavigateToPath("/next"))) {
            $0.navigationState = .folder("/next")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/seed"))]
            $0.forwardHistory = []
        }
        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/seed"), next: .folder("/next"))))
        await store.receive(.delegate(.navigateToState(.folder("/next"))))

        // back: /next → /seed
        await store.send(.internal(.performNavigation(.back))) {
            $0.navigationState = .folder("/seed")
            $0.backHistory = []
            $0.forwardHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/next"))]
        }
        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/next"), next: .folder("/seed"))))
        await store.receive(.delegate(.navigateToState(.folder("/seed"))))
    }

    // MARK: - EVM-001-forward_page_history

    /// forwardHistory가 비어있을 때 forward 네비게이션은 no-op이다.
    func testForwardOnEmptyHistoryIsNoop() async {
        let store = makeStore(seedPath: "/seed")

        await store.send(.internal(.performNavigation(.forward)))
    }

    /// back 후 forward하면 원래 상태로 복귀한다.
    /// backHistory와 forwardHistory가 올바르게 재조정된다.
    func testForwardAfterBackRestoresForwardEntry() async {
        let store = makeStore(seedPath: "/seed")

        // /seed → /next
        await store.send(.internal(.performNavigateToPath("/next"))) {
            $0.navigationState = .folder("/next")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/seed"))]
            $0.forwardHistory = []
        }
        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/seed"), next: .folder("/next"))))
        await store.receive(.delegate(.navigateToState(.folder("/next"))))

        // back: /next → /seed
        await store.send(.internal(.performNavigation(.back))) {
            $0.navigationState = .folder("/seed")
            $0.backHistory = []
            $0.forwardHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/next"))]
        }
        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/next"), next: .folder("/seed"))))
        await store.receive(.delegate(.navigateToState(.folder("/seed"))))

        // forward: /seed → /next
        await store.send(.internal(.performNavigation(.forward))) {
            $0.navigationState = .folder("/next")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/seed"))]
            $0.forwardHistory = []
        }
        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/seed"), next: .folder("/next"))))
        await store.receive(.delegate(.navigateToState(.folder("/next"))))
    }

    // MARK: - EVM-001-show_page_history

    /// history index 점프: backHistory의 첫 번째 엔트리(index 0)로 점프하면
    /// backHistory는 비어있고, 나머지는 forwardHistory로 이동한다.
    func testGoToHistoryIndexRebalancesBackAndForward() async {
        let store = makeStore(seedPath: "/seed")
        store.exhaustivity = .off

        // /seed → /a → /b → /c
        await store.send(.internal(.performNavigateToPath("/a")))
        await store.receive(.delegate(.resetComposer))
        await store.receive(\.delegate)
        await store.receive(\.delegate)

        await store.send(.internal(.performNavigateToPath("/b")))
        await store.receive(.delegate(.resetComposer))
        await store.receive(\.delegate)
        await store.receive(\.delegate)

        await store.send(.internal(.performNavigateToPath("/c")))
        await store.receive(.delegate(.resetComposer))
        await store.receive(\.delegate)
        await store.receive(\.delegate)

        // 현재: navigationState=/c, backHistory=[/seed, /a, /b]
        // backHistory index 0 = /seed로 점프
        await store.send(.internal(.performNavigation(.history(index: 0, isBackHistory: true)))) {
            $0.navigationState = .folder("/seed")
            $0.backHistory = []
            // forwardHistory: 현재(/c) + newForwardHistory.reversed()(/a, /b)
            $0.forwardHistory = [
                ContentPageNavigationHistorySnapshot(navigationState: .folder("/c")),
                ContentPageNavigationHistorySnapshot(navigationState: .folder("/a")),
                ContentPageNavigationHistorySnapshot(navigationState: .folder("/b")),
            ]
        }

        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/c"), next: .folder("/seed"))))
        await store.receive(.delegate(.navigateToState(.folder("/seed"))))

        await store.finish()
    }

    // MARK: - EVM-001-go_to_enclosing_directory

    /// 루트 경로("/")에서 enclosing directory 네비게이션은 no-op이다.
    func testEnclosingDirectoryFromRootIsNoop() async {
        let store = makeStore(seedPath: "/")

        await store.send(.internal(.performNavigation(.enclosingDirectory)))
    }

    /// 하위 경로에서 enclosing directory 네비게이션은 부모 경로로 이동한다.
    /// backHistory에 현재 스냅샷이 추가되고 forwardHistory가 초기화된다.
    func testEnclosingDirectoryMovesToParent() async {
        let store = makeStore(seedPath: "/a/b")

        await store.send(.internal(.performNavigation(.enclosingDirectory))) {
            $0.navigationState = .folder("/a")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/a/b"))]
            $0.forwardHistory = []
        }

        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/a/b"), next: .folder("/a"))))
        await store.receive(.delegate(.navigateToState(.folder("/a"))))
    }

    // MARK: - EVM-001-view_current_page_title

    // EVM-001-view_current_page_title: titlePath는 seedInitialFolderPath에서만 설정되며
    // 리듀서가 직접 업데이트하지 않는다. View 레이어에서 navigationState로부터 파생된다.
    // 이 테스트는 아키텍처적 사실을 문서화한다.
    func testViewCurrentPageTitleReflectsRoute() async {
        let store = makeStore(seedPath: "/seed")

        // 초기 titlePath는 seed 시 설정됨
        XCTAssertEqual(store.state.titlePath, "/seed")

        // /next로 네비게이션 후 navigationState는 변경되지만
        // titlePath는 리듀서에서 업데이트되지 않는다.
        await store.send(.internal(.performNavigateToPath("/next"))) {
            $0.navigationState = .folder("/next")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/seed"))]
            $0.forwardHistory = []
            // titlePath는 그대로 "/seed" — 리듀서가 변경하지 않음
        }
        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/seed"), next: .folder("/next"))))
        await store.receive(.delegate(.navigateToState(.folder("/next"))))

        // titlePath가 여전히 seed 값을 유지 — view 레이어 책임
        XCTAssertEqual(store.state.titlePath, "/seed")
        XCTAssertEqual(store.state.navigationState, .folder("/next"))
    }
}

@MainActor
private func makeStore(
    seedPath: String,
) -> TestStore<ContentPageNavigationFeature.State, ContentPageNavigationFeature.Action> {
    var state = ContentPageNavigationFeature.State()
    state.seedInitialFolderPath(seedPath)
    return TestStore(initialState: state) {
        ContentPageNavigationFeature()
    }
}
