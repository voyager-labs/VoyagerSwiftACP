// FLOW-ID: fmw.manage_file_manager_window_panes
import ComposableArchitecture
@testable import Voyager
@testable import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import XCTest

/// FMW-002 sidebar toggle focused-window route 검증.
///
/// WindowManagerAction.window(.toggleSidebar)가 sendCommandToFocusedWindow을 통해
/// focused window로만 .window(.request(.toggleSidebar))를 라우팅하는지 검증한다.
/// background window는 sidebarVisible/width 모두 불변이다.
///
/// focused window가 없으면 toggleSidebar는 no-op이다.
///
/// 사이드바 토글 내부 동작(setSidebarVisible, width clamping, divider drag, preference projection,
/// inspector visibility)은 package-scoped FMW-002 Specs(FMW002ManageFileManagerWindowPanesTests)
/// 소유이므로 이 파일에서 단언하지 않는다.
@MainActor
final class ManageFileManagerWindowPanesFlowTests: XCTestCase {
    // MARK: - File-local helpers

    /// focusedID와 윈도우 목록으로 WindowManagerFeature.State를 생성한다.
    private static func makeState(
        focusedID: UUID?,
        windows: [(UUID, String?)],
    ) -> WindowManagerFeature.State {
        var state = WindowManagerFeature.State()
        state.windows = .init(uniqueElements: windows.map { id, path in
            WindowSessionState(id: id, window: .makeInitial(path: path))
        })
        state.focusedWindowID = focusedID
        return state
    }

    /// WindowManagerFeature TestStore를 생성한다.
    private static func makeStore(
        initialState: WindowManagerFeature.State = WindowManagerFeature.State(),
        uuid: UUID? = nil,
        configureDependencies: ((inout DependencyValues) -> Void)? = nil,
    ) -> TestStore<WindowManagerFeature.State, WindowManagerFeature.Action> {
        TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            if let uuid {
                $0.uuid = .constant(uuid)
            }
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.showIfNeeded = { false }
            configureDependencies?(&$0)
        }
    }

    /// 테스트용 경로 상수
    private enum Spec {
        static let focusedPath = "/focused-pane"
        static let backgroundPath = "/background-pane"
    }

    // MARK: - FMW-002-toggle_sidebar_focused_window

    /// FMW-002-toggle_sidebar_focused_window: focused window로만 sidebar toggle 라우팅
    ///
    /// WindowManagerAction.window(.toggleSidebar)가 focused window로만
    /// .window(.request(.toggleSidebar))를 전달하고, background window는
    /// sidebarVisible/width 모두 불변인지 검증한다.
    /// - 검증 내용: toggleSidebar 전송 시 focusedID로만 명령 라우팅, background 상태 불변
    /// - 사전 조건: 2개 윈도우(focusedID, backgroundID) 존재, focusedID = focused
    /// - 기대 결과: focusedID로만 .window(.request(.toggleSidebar)) 방출,
    ///   background sidebarVisible/width 불변
    func test_toggleSidebar_focusedWindowIsolation() async throws {
        let focusedID = UUID()
        let backgroundID = UUID()

        let store = Self.makeStore(initialState: Self.makeState(
            focusedID: focusedID,
            windows: [(focusedID, Spec.focusedPath), (backgroundID, Spec.backgroundPath)],
        ))

        // store.exhaustivity = .off: child reducer 내부 라우팅 체인은 package-scoped 테스트가 검증한다.
        store.exhaustivity = .off

        // background window의 초기 sidebarVisible/width 저장
        let initialBackgroundVisible = try XCTUnwrap(
            store.state.windows[id: backgroundID]?.window.sidebar.sidebarVisible,
        )
        let initialBackgroundWidth = try XCTUnwrap(
            store.state.windows[id: backgroundID]?.window.sidebar.sidebarWidth,
        )

        await store.send(.window(.toggleSidebar))

        // focused window로만 toggleSidebar 명령이 라우팅되었는지 확인
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .request(.toggleSidebar))) = action else { return false }
            return id == focusedID
        }

        // background window는 sidebarVisible/width 모두 불변
        let backgroundWindow = try XCTUnwrap(store.state.windows[id: backgroundID])
        XCTAssertEqual(
            backgroundWindow.window.sidebar.sidebarVisible,
            initialBackgroundVisible,
            "background window의 sidebarVisible은 toggleSidebar 후에도 변경되지 않아야 한다",
        )
        XCTAssertEqual(
            backgroundWindow.window.sidebar.sidebarWidth,
            initialBackgroundWidth,
            "background window의 sidebarWidth는 toggleSidebar 후에도 변경되지 않아야 한다",
        )
    }

    /// FMW-002-toggle_sidebar_focused_window: focused window 없으면 toggleSidebar no-op
    ///
    /// focusedWindowID가 nil일 때 WindowManagerAction.window(.toggleSidebar)가
    /// 아무 window로도 명령을 전달하지 않고 상태가 불변인지 검증한다.
    /// - 검증 내용: focusedWindowID == nil일 때 toggleSidebar 전송 후 상태 변화 없음
    /// - 사전 조건: 1개 윈도우(backgroundID) 존재하지만 focused 없음
    /// - 기대 결과: 어떤 window로도 .request(.toggleSidebar) 방출되지 않음, 상태 불변
    func test_toggleSidebar_noFocusedWindow_isNoOp() async {
        let backgroundID = UUID()

        let store = Self.makeStore(initialState: Self.makeState(
            focusedID: nil,
            windows: [(backgroundID, Spec.backgroundPath)],
        ))

        // focusedWindowID가 nil이면 sendCommandToFocusedWindow가 .none 반환
        await store.send(.window(.toggleSidebar))
    }

    // MARK: - FMW-002-toggle_sidebar_multi_window_background_stable

    /// FMW-002-toggle_sidebar_multi_window_background_stable: 멀티 윈도우 환경에서
    /// focused window toggleSidebar가 background window에 영향을 주지 않음
    ///
    /// 2개 이상의 윈도우가 있을 때 focused window의 toggleSidebar가
    /// 다른 모든 window의 sidebarVisible/width에 영향을 주지 않는지 검증한다.
    /// - 검증 내용: focused window toggleSidebar 후 background window들의 sidebarVisible/width 불변
    /// - 사전 조건: 3개 윈도우(focused, background1, background2) 존재
    /// - 기대 결과: background1, background2의 sidebarVisible/width 변경 없음
    func test_toggleSidebar_multiWindowBackgroundStable() async throws {
        let focusedID = UUID()
        let background1ID = UUID()
        let background2ID = UUID()

        let store = Self.makeStore(initialState: Self.makeState(
            focusedID: focusedID,
            windows: [
                (focusedID, Spec.focusedPath),
                (background1ID, "/bg1"),
                (background2ID, "/bg2"),
            ],
        ))

        store.exhaustivity = .off

        // background window들의 초기 sidebarVisible/width 저장
        let bg1Visible = try XCTUnwrap(
            store.state.windows[id: background1ID]?.window.sidebar.sidebarVisible,
        )
        let bg1Width = try XCTUnwrap(
            store.state.windows[id: background1ID]?.window.sidebar.sidebarWidth,
        )
        let bg2Visible = try XCTUnwrap(
            store.state.windows[id: background2ID]?.window.sidebar.sidebarVisible,
        )
        let bg2Width = try XCTUnwrap(
            store.state.windows[id: background2ID]?.window.sidebar.sidebarWidth,
        )

        await store.send(.window(.toggleSidebar))
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .request(.toggleSidebar))) = action else { return false }
            return id == focusedID
        }

        // 모든 background window sidebarVisible/width 불변
        for bgID in [background1ID, background2ID] {
            let bg = try XCTUnwrap(store.state.windows[id: bgID])
            let expectedVisible = bgID == background1ID ? bg1Visible : bg2Visible
            let expectedWidth = bgID == background1ID ? bg1Width : bg2Width
            XCTAssertEqual(
                bg.window.sidebar.sidebarVisible,
                expectedVisible,
                "background window \(bgID)의 sidebarVisible은 변경되지 않아야 한다",
            )
            XCTAssertEqual(
                bg.window.sidebar.sidebarWidth,
                expectedWidth,
                "background window \(bgID)의 sidebarWidth는 변경되지 않아야 한다",
            )
        }
    }
}
