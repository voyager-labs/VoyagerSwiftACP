import ComposableArchitecture
import VoyagerEntitiesCollection
@testable import VoyagerFeaturesContentPageNavigation
import VoyagerShared
import XCTest

@MainActor
final class EVM001ContentPageNavigationRoutingTests: XCTestCase {
    // MARK: - EVM-001-navigate_pages

    /// EVM-001-navigate_pages: 동일 경로 재네비게이션 시 history 미기록
    /// 현재 위치와 동일한 경로로 navigate할 때 history에 새 항목이 추가되지 않음을 확인한다.
    /// - 검증 내용: performNavigateToPath가 같은 경로에서 backHistory/forwardHistory 불변, resetComposer 미발생
    /// - 사전 조건: seedPath="/seed"로 초기화된 TestStore
    /// - 기대 결과: logDAUNavigation + navigateToState 델리게이트만 발생, 상태 변화 없음
    func testDirectNavigateToSamePathDoesNotRecordHistory() async {
        let store = makeNavigationStore(seedPath: "/seed")

        await store.send(.internal(.performNavigateToPath("/seed")))

        await store.receive(.delegate(.logDAUNavigation(
            previous: .folder("/seed"),
            next: .folder("/seed"),
            identity: .direct,
        )))
        await store.receive(.delegate(.navigateToState(.folder("/seed"))))
    }

    /// EVM-001-navigate_pages: 다른 경로 네비게이션 시 history 기록 및 델리게이트 발생
    /// 다른 경로로 navigate하면 backHistory에 이전 상태가 기록되고 forwardHistory가 초기화된다.
    /// - 검증 내용: performNavigateToPath로 다른 경로 이동 시 backHistory/forwardHistory 재조정, 델리게이트 순서 resetComposer → logDAU →
    /// navigateToState
    /// - 사전 조건: seedPath="/seed"로 초기화된 TestStore
    /// - 기대 결과: navigationState="/next", backHistory=["/seed"], forwardHistory=[], 델리게이트 3개 순차 발생
    func testDirectNavigateRecordsHistoryAndEmitsDelegates() async {
        let store = makeNavigationStore(seedPath: "/seed")

        await store.send(.internal(.performNavigateToPath("/next"))) {
            $0.navigationState = .folder("/next")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/seed"))]
            $0.forwardHistory = []
        }

        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(
            previous: .folder("/seed"),
            next: .folder("/next"),
            identity: .direct,
        )))
        await store.receive(.delegate(.navigateToState(.folder("/next"))))
    }

    /// EVM-001-navigate_pages: 최근 항목 네비게이션 시 history 기록 및 델리게이트 순차 발생 검증
    /// 최근 항목으로 직접 네비게이션하면 backHistory에 이전 상태가 기록되고 델리게이트가 순차 발생한다.
    /// - 검증 내용: performShowRecents 액션이 navigationState를 .recents로 변경하고 backHistory/forwardHistory를 재조정하는지 확인
    /// - 사전 조건: seedPath="/seed"로 초기화된 TestStore
    /// - 기대 결과: navigationState=.recents, backHistory=["/seed"], forwardHistory=[], resetComposer → logDAU →
    /// navigateToState 순차 발생
    func testDirectShowRecentsRecordsHistoryAndEmitsDelegatesInOrder() async {
        let store = makeNavigationStore(seedPath: "/seed")

        await store.send(.internal(.performShowRecents)) {
            $0.navigationState = .recents
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/seed"))]
            $0.forwardHistory = []
        }

        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(
            previous: .folder("/seed"),
            next: .recents,
            identity: .direct,
        )))
        await store.receive(.delegate(.navigateToState(.recents)))
    }

    /// EVM-001-navigate_pages: 태그 네비게이션 시 history 기록 및 델리게이트 순차 발생 검증
    /// 태그 경로로 직접 네비게이션하면 backHistory에 이전 상태가 기록되고 델리게이트가 순차 발생한다.
    /// - 검증 내용: performShowTag("work") 액션이 navigationState를 .tags("work")로 변경하고 backHistory/forwardHistory를 재조정하는지 확인
    /// - 사전 조건: seedPath="/seed"로 초기화된 TestStore
    /// - 기대 결과: navigationState=.tags("work"), backHistory=["/seed"], forwardHistory=[], resetComposer → logDAU →
    /// navigateToState 순차 발생
    func testDirectShowTagRecordsHistoryAndEmitsDelegatesInOrder() async {
        let store = makeNavigationStore(seedPath: "/seed")

        await store.send(.internal(.performShowTag("work"))) {
            $0.navigationState = .tags("work")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/seed"))]
            $0.forwardHistory = []
        }

        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(
            previous: .folder("/seed"),
            next: .tags("work"),
            identity: .direct,
        )))
        await store.receive(.delegate(.navigateToState(.tags("work"))))
    }

    /// EVM-001-navigate_pages: 컴퓨터 루트 네비게이션 시 history 기록 및 델리게이트 순차 발생 검증
    /// 컴퓨터 루트로 직접 네비게이션하면 backHistory에 이전 상태가 기록되고 델리게이트가 순차 발생한다.
    /// - 검증 내용: performShowComputer 액션이 navigationState를 .computer로 변경하고 backHistory/forwardHistory를 재조정하는지 확인
    /// - 사전 조건: seedPath="/seed"로 초기화된 TestStore
    /// - 기대 결과: navigationState=.computer, backHistory=["/seed"], forwardHistory=[], resetComposer → logDAU →
    /// navigateToState 순차 발생
    func testDirectShowComputerRecordsHistoryAndEmitsDelegatesInOrder() async {
        let store = makeNavigationStore(seedPath: "/seed")

        await store.send(.internal(.performShowComputer)) {
            $0.navigationState = .computer
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/seed"))]
            $0.forwardHistory = []
        }

        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(
            previous: .folder("/seed"),
            next: .computer,
            identity: .direct,
        )))
        await store.receive(.delegate(.navigateToState(.computer)))
    }

    /// EVM-001-navigate_pages: 컬렉션으로 history back 시 resetComposer 미발생 검증
    /// 컬렉션 경로로 history back하면 resetComposer가 발생하지 않고 다른 델리게이트만 발생한다.
    /// - 검증 내용: performNavigation(.back)이 컬렉션 경로에서 resetComposer를 발생시키지 않고 logDAU와 navigateToState만 발생하는지 확인
    /// - 사전 조건: navigationState=.folder("/folder"), backHistory에 컬렉션 경로 스냅샷 존재
    /// - 기대 결과: navigationState가 컬렉션으로 복원, resetComposer 미발생, logDAU → navigateToState 순차 발생
    func testHistoryNavigationToCollectionDoesNotEmitResetComposer() async {
        let collectionRoute = ContentPageNavigationRoute.collection(ContentPageCollectionNavigation(
            kind: .temporary,
            context: CollectionContext(query: "", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))

        var initial = ContentPageNavigationFeature.State()
        initial.seedInitialFolderPath("/folder")
        initial.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: collectionRoute)]

        let store = TestStore(initialState: initial) {
            ContentPageNavigationFeature()
        }

        await store.send(.internal(.performNavigation(.back))) {
            $0.navigationState = collectionRoute
            $0.backHistory = []
            $0.forwardHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/folder"))]
        }

        await store.receive(.delegate(.logDAUNavigation(
            previous: .folder("/folder"),
            next: collectionRoute,
            identity: .back,
        )))
        await store.receive(.delegate(.navigateToState(collectionRoute)))
    }

    /// EVM-001-navigate_pages: 컬렉션 파일 열기 준비 시 현재 스냅샷 기록 검증
    /// 컬렉션 파일 열기 준비 시 현재 navigationState가 backHistory에 스냅샷으로 기록된다.
    /// - 검증 내용: prepareCollectionFileOpen 액션이 backHistory에 현재 navigationState(.recents)를 스냅샷으로 추가하는지 확인
    /// - 사전 조건: navigationState=.recents로 설정된 TestStore
    /// - 기대 결과: backHistory에 .recents 스냅샷 추가, forwardHistory 초기화
    func testPrepareCollectionFileOpenRecordsActualCurrentSnapshot() async {
        var initial = ContentPageNavigationFeature.State()
        initial.navigationState = .recents

        let store = TestStore(initialState: initial) {
            ContentPageNavigationFeature()
        }

        let url = URL(fileURLWithPath: "/folder/sample.voycoll")

        await store.send(.internal(.prepareCollectionFileOpen(url))) {
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .recents)]
            $0.forwardHistory = []
        }
    }

    // MARK: - EVM-001-go_page_history_back

    /// EVM-001-go_page_history_back: 빈 backHistory에서 back 네비게이션 no-op
    /// backHistory가 비어있을 때 back 액션은 아무 상태 변화나 델리게이트도 발생시키지 않는다.
    /// - 검증 내용: performNavigation(.back)이 빈 backHistory에서 no-op인지 확인
    /// - 사전 조건: seedPath="/seed"로 초기화된 TestStore (backHistory = [])
    /// - 기대 결과: 상태 변화 없음, 델리게이트 발생 없음
    func testBackOnEmptyHistoryIsNoop() async {
        let store = makeNavigationStore(seedPath: "/seed")

        await store.send(.internal(.performNavigation(.back)))
    }

    /// EVM-001-go_page_history_back: back 네비게이션 시 현재 상태를 forwardHistory로 이동하고 이전 상태 복원
    /// back 액션 수행 시 현재 상태가 forwardHistory에 push되고 backHistory 마지막 항목으로 복원된다.
    /// - 검증 내용: back 후 navigationState 복원, backHistory pop, forwardHistory push, 델리게이트 순서 resetComposer → logDAU →
    /// navigateToState
    /// - 사전 조건: /seed → /next로 이동하여 backHistory=["/seed"]인 TestStore
    /// - 기대 결과: navigationState="/seed", backHistory=[], forwardHistory=["/next"], 델리게이트 3개 순차 발생
    func testBackMovesCurrentToForwardAndRestoresPrevious() async {
        let store = makeNavigationStore(seedPath: "/seed")

        // 먼저 /next로 이동하여 backHistory를 채운다
        await store.send(.internal(.performNavigateToPath("/next"))) {
            $0.navigationState = .folder("/next")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/seed"))]
            $0.forwardHistory = []
        }
        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(
            previous: .folder("/seed"),
            next: .folder("/next"),
            identity: .direct,
        )))
        await store.receive(.delegate(.navigateToState(.folder("/next"))))

        // back: /next → /seed
        await store.send(.internal(.performNavigation(.back))) {
            $0.navigationState = .folder("/seed")
            $0.backHistory = []
            $0.forwardHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/next"))]
        }
        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(
            previous: .folder("/next"),
            next: .folder("/seed"),
            identity: .back,
        )))
        await store.receive(.delegate(.navigateToState(.folder("/seed"))))
    }

    // MARK: - EVM-001-forward_page_history

    /// EVM-001-forward_page_history: 빈 forwardHistory에서 forward 네비게이션 no-op
    /// forwardHistory가 비어있을 때 forward 액션은 아무 상태 변화나 델리게이트도 발생시키지 않는다.
    /// - 검증 내용: performNavigation(.forward)이 빈 forwardHistory에서 no-op인지 확인
    /// - 사전 조건: seedPath="/seed"로 초기화된 TestStore (forwardHistory = [])
    /// - 기대 결과: 상태 변화 없음, 델리게이트 발생 없음
    func testForwardOnEmptyHistoryIsNoop() async {
        let store = makeNavigationStore(seedPath: "/seed")

        await store.send(.internal(.performNavigation(.forward)))
    }

    /// EVM-001-forward_page_history: back 후 forward 시 원래 상태로 복귀
    /// back으로 이동한 후 forward하면 back/forward history가 올바르게 재조정되며 원래 상태로 복귀한다.
    /// - 검증 내용: back 후 forward 시 navigationState 복원, backHistory/forwardHistory 재조정, 델리게이트 순서
    /// - 사전 조건: /seed → /next 이동 후 back으로 /seed로 복귀한 TestStore (forwardHistory=["/next"])
    /// - 기대 결과: navigationState="/next", backHistory=["/seed"], forwardHistory=[], 델리게이트 3개 순차 발생
    func testForwardAfterBackRestoresForwardEntry() async {
        let store = makeNavigationStore(seedPath: "/seed")

        // /seed → /next
        await store.send(.internal(.performNavigateToPath("/next"))) {
            $0.navigationState = .folder("/next")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/seed"))]
            $0.forwardHistory = []
        }
        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(
            previous: .folder("/seed"),
            next: .folder("/next"),
            identity: .direct,
        )))
        await store.receive(.delegate(.navigateToState(.folder("/next"))))

        // back: /next → /seed
        await store.send(.internal(.performNavigation(.back))) {
            $0.navigationState = .folder("/seed")
            $0.backHistory = []
            $0.forwardHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/next"))]
        }
        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(
            previous: .folder("/next"),
            next: .folder("/seed"),
            identity: .back,
        )))
        await store.receive(.delegate(.navigateToState(.folder("/seed"))))

        // forward: /seed → /next
        await store.send(.internal(.performNavigation(.forward))) {
            $0.navigationState = .folder("/next")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/seed"))]
            $0.forwardHistory = []
        }
        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(
            previous: .folder("/seed"),
            next: .folder("/next"),
            identity: .forward,
        )))
        await store.receive(.delegate(.navigateToState(.folder("/next"))))
    }

    // MARK: - EVM-001-show_page_history

    /// EVM-001-show_page_history: history index 점프 시 back/forward history 재조정
    /// backHistory의 특정 인덱스로 점프하면 점프 지점 이전은 backHistory, 이후와 현재는 forwardHistory로 재배치된다.
    /// - 검증 내용: performNavigation(.history(index:isBackHistory:))로 backHistory[0] 점프 시 backHistory/forwardHistory 재조정
    /// - 사전 조건: /seed → /a → /b → /c로 이동하여 backHistory=["/seed", "/a", "/b"]인 TestStore
    /// - 기대 결과: navigationState="/seed", backHistory=[], forwardHistory=["/c", "/a", "/b"], 델리게이트 3개 발생
    func testGoToHistoryIndexRebalancesBackAndForward() async {
        let store = makeNavigationStore(seedPath: "/seed")
        // 설정 단계의 내부 델리게이트는 이 시나리오의 검증 대상이 아니므로 끈다.
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
        await store.receive(.delegate(.logDAUNavigation(
            previous: .folder("/c"),
            next: .folder("/seed"),
            identity: .history,
        )))
        await store.receive(.delegate(.navigateToState(.folder("/seed"))))

        await store.finish()
    }

    /// EVM-001-show_page_history: history 최대 10개 항목 제한 검증
    /// 네비게이션 history가 10개 항목으로 제한되어 초과 시 가장 오래된 항목이 제거된다.
    /// - 검증 내용: 12번 연속 네비게이션 후 backHistory가 10개로 제한되고 가장 오래된 항목이 제거되는지 확인
    /// - 사전 조건: seedPath="/seed"로 초기화된 TestStore
    /// - 기대 결과: backHistory.count == 10, 첫 항목이 "/p/1", 마지막 항목이 "/p/10"
    func testHistoryIsTrimmedToTenEntries() async {
        let store = makeNavigationStore(seedPath: "/seed")
        // 12번의 네비게이션 설정 단계 델리게이트는 이 시나리오의 검증 대상이 아니므로 끈다.
        store.exhaustivity = .off

        for index in 0 ..< 12 {
            await store.send(.internal(.performNavigateToPath("/p/\(index)")))
            await store.receive(.delegate(.resetComposer))
            await store.receive(\.delegate)
            await store.receive(\.delegate)
        }

        XCTAssertEqual(store.state.backHistory.count, 10)
        XCTAssertEqual(store.state.forwardHistory.count, 0)
        XCTAssertEqual(store.state.navigationState, .folder("/p/11"))

        XCTAssertEqual(store.state.backHistory.first?.navigationState, .folder("/p/1"))
        XCTAssertEqual(store.state.backHistory.last?.navigationState, .folder("/p/10"))

        await store.finish()
    }

    // MARK: - EVM-001-go_to_enclosing_directory

    /// EVM-001-go_to_enclosing_directory: 루트 경로에서 상위 디렉토리 네비게이션 no-op
    /// 루트 경로("/")에서 enclosing directory 액션은 부모가 없으므로 no-op이다.
    /// - 검증 내용: performNavigation(.enclosingDirectory)가 루트 경로에서 no-op인지 확인
    /// - 사전 조건: seedPath="/"로 초기화된 TestStore
    /// - 기대 결과: 상태 변화 없음, 델리게이트 발생 없음
    func testEnclosingDirectoryFromRootIsNoop() async {
        let store = makeNavigationStore(seedPath: "/")

        await store.send(.internal(.performNavigation(.enclosingDirectory)))
    }

    /// EVM-001-go_to_enclosing_directory: 하위 경로에서 부모 경로로 이동
    /// 하위 경로에서 enclosing directory 액션 시 부모 경로로 이동하고 backHistory에 현재 스냅샷이 추가된다.
    /// - 검증 내용: performNavigation(.enclosingDirectory)로 부모 경로 이동, backHistory push, forwardHistory 초기화, 델리게이트 순서
    /// - 사전 조건: seedPath="/a/b"로 초기화된 TestStore
    /// - 기대 결과: navigationState="/a", backHistory=["/a/b"], forwardHistory=[], 델리게이트 3개 순차 발생
    func testEnclosingDirectoryMovesToParent() async {
        let store = makeNavigationStore(seedPath: "/a/b")

        await store.send(.internal(.performNavigation(.enclosingDirectory))) {
            $0.navigationState = .folder("/a")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/a/b"))]
            $0.forwardHistory = []
        }

        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(
            previous: .folder("/a/b"),
            next: .folder("/a"),
            identity: .enclosingDirectory,
        )))
        await store.receive(.delegate(.navigateToState(.folder("/a"))))
    }

    // MARK: - EVM-001-view_current_page_title

    /// EVM-001-view_current_page_title: titlePath는 seed에서만 설정되며 리듀서가 직접 업데이트하지 않음
    /// 네비게이션 후 navigationState는 변경되지만 titlePath는 리듀서에서 업데이트되지 않아 view 레이어 책임임을 확인한다.
    /// - 검증 내용: navigate 후 titlePath 불변, navigationState만 변경, 아키텍처적 책임 분리 문서화
    /// - 사전 조건: seedPath="/seed"로 초기화된 TestStore
    /// - 기대 결과: 초기 titlePath="/seed", navigate("/next") 후에도 titlePath="/seed" 유지, navigationState만 "/next"로 변경
    func testViewCurrentPageTitleReflectsRoute() async {
        let store = makeNavigationStore(seedPath: "/seed")

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
        await store.receive(.delegate(.logDAUNavigation(
            previous: .folder("/seed"),
            next: .folder("/next"),
            identity: .direct,
        )))
        await store.receive(.delegate(.navigateToState(.folder("/next"))))

        // titlePath가 여전히 seed 값을 유지 — view 레이어 책임
        XCTAssertEqual(store.state.titlePath, "/seed")
        XCTAssertEqual(store.state.navigationState, .folder("/next"))
    }
}
