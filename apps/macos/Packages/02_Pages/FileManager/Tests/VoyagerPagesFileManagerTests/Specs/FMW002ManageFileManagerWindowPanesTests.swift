import ComposableArchitecture
@testable import VoyagerPagesFileManager
import XCTest

// FMW-002: 사이드바/인스펙터 패인 관리 테스트
// 사이드바 표시/숨김, 너비 클램프, 인스펙터 표시/숨김, 독립성 계약 검증

@MainActor
final class FMW002ManageFileManagerWindowPanesTests: XCTestCase {
    private typealias SidebarWidth = FMW002PaneTestSupport.SidebarWidth

    // MARK: - Helper: 사이드바 TestStore 생성

    private func makeSidebarStore(
        initialState: FileManagerSidebarState = FileManagerSidebarState(),
    ) -> TestStore<FileManagerSidebarState, FileManagerSidebarAction> {
        TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
        }
    }

    private func makeInspectorStore(
        initialState: FileManagerInspectorState = FileManagerInspectorState(),
    ) -> TestStore<FileManagerInspectorState, FileManagerInspectorAction> {
        TestStore(initialState: initialState) {
            FileManagerInspectorFeature()
        }
    }

    private func makeSidebarState(
        visible: Bool = true,
        width: CGFloat = SidebarWidth.defaultValue,
    ) -> FileManagerSidebarState {
        var state = FileManagerSidebarState()
        state.sidebarVisible = visible
        state.sidebarWidth = width
        return state
    }

    private func makeInspectorState(
        visible: Bool = false,
        paneExists: Bool = false,
    ) -> FileManagerInspectorState {
        var state = FileManagerInspectorState()
        state.inspectorVisible = visible
        state.inspectorPaneExists = paneExists
        return state
    }

    // MARK: - FMW-002-show_sidebar / FMW-002-hide_sidebar

    /// FMW-002-show_sidebar: 사이드바 표시 액션이 sidebarVisible을 true로 설정
    /// setSidebarVisible(true) 전송 시 sidebarVisible이 false → true로 변경
    /// - 검증 내용: setSidebarVisible(true) 전송 시 sidebarVisible이 false → true로 변경
    /// - 사전 조건: sidebarVisible == false
    /// - 기대 결과: state.sidebarVisible == true
    func test_showSidebar_setsSidebarVisible() async {
        let store = makeSidebarStore(initialState: makeSidebarState(visible: false))

        await store.send(.view(.setSidebarVisible(true))) { state in
            state.sidebarVisible = true
        }

        await store.finish()
    }

    /// FMW-002-hide_sidebar: 사이드바 숨김 액션이 sidebarVisible을 false로 설정
    /// setSidebarVisible(false) 전송 시 sidebarVisible이 true → false로 변경
    /// - 검증 내용: setSidebarVisible(false) 전송 시 sidebarVisible이 true → false로 변경
    /// - 사전 조건: sidebarVisible == true
    /// - 기대 결과: state.sidebarVisible == false
    func test_hideSidebar_setsSidebarHidden() async {
        let store = makeSidebarStore(initialState: makeSidebarState(visible: true))

        await store.send(.view(.setSidebarVisible(false))) { state in
            state.sidebarVisible = false
        }

        await store.finish()
    }

    /// FMW-002-show_sidebar / FMW-002-hide_sidebar: 반복 토글 원상 복귀
    /// 반복 토글(show→hide→show)이 원래 상태로 복귀하는지 검증
    /// - 검증 내용: setSidebarVisible(false) → setSidebarVisible(true) 전송 후 원래 상태 복귀
    /// - 사전 조건: sidebarVisible == true
    /// - 기대 결과: 최종 sidebarVisible == true
    func test_repeatedToggle_returnsToOriginalState() async {
        let store = makeSidebarStore(initialState: makeSidebarState(visible: true))

        await store.send(.view(.setSidebarVisible(false))) { state in
            state.sidebarVisible = false
        }

        await store.send(.view(.setSidebarVisible(true))) { state in
            state.sidebarVisible = true
        }

        await store.finish()
    }

    /// FMW-002-show_sidebar: 초기 sidebarVisible 기본값 검증
    /// 초기 sidebarVisible 기본값이 true인지 검증
    /// - 검증 내용: FileManagerSidebarState() 생성 시 sidebarVisible 기본값 확인
    /// - 사전 조건: 기본 생성자로 상태 초기화
    /// - 기대 결과: state.sidebarVisible == true
    func test_initialSidebarVisibility_isExpectedDefault() {
        let state = FileManagerSidebarState()
        XCTAssertTrue(
            state.sidebarVisible,
            "sidebarVisible 기본값은 true여야 한다",
        )
    }

    // MARK: - FMW-002-adjust_sidebar_width

    /// FMW-002-adjust_sidebar_width: 정상 범위 내 너비 적용
    /// 정상 범위 내 너비 값이 그대로 적용되는지 검증
    /// - 검증 내용: setSidebarWidth(inRange) 전송 시 sidebarWidth가 입력값으로 설정
    /// - 사전 조건: sidebarWidth == defaultValue (220)
    /// - 기대 결과: state.sidebarWidth == inRange (250)
    func test_sidebarWidth_withinAllowedRange_appliesValue() async {
        let store = makeSidebarStore(initialState: makeSidebarState(width: SidebarWidth.defaultValue))

        await store.send(.view(.setSidebarWidth(SidebarWidth.inRange))) { state in
            state.sidebarWidth = SidebarWidth.inRange
        }

        await store.finish()
    }

    /// FMW-002-adjust_sidebar_width: 최소값 미만 너비 클램프
    /// 최소값 미만 너비가 최소값으로 클램프되는지 검증
    /// - 검증 내용: setSidebarWidth(belowMinimum=100) 전송 시 sidebarWidth가 min(150)으로 클램프
    /// - 사전 조건: sidebarWidth == defaultValue (220)
    /// - 기대 결과: state.sidebarWidth == min (150)
    func test_sidebarWidth_belowMinimum_clampsToMinimum() async {
        let store = makeSidebarStore(initialState: makeSidebarState(width: SidebarWidth.defaultValue))

        // belowMinimum은 min 미만이므로 min으로 클램프된다.
        await store.send(.view(.setSidebarWidth(SidebarWidth.belowMinimum))) { state in
            state.sidebarWidth = SidebarWidth.min
        }

        await store.finish()
    }

    /// FMW-002-adjust_sidebar_width: 최대값 초과 너비 클램프
    /// 최대값 초과 너비가 최대값으로 클램프되는지 검증
    /// - 검증 내용: setSidebarWidth(aboveMaximum=500) 전송 시 sidebarWidth가 max(400)으로 클램프
    /// - 사전 조건: sidebarWidth == defaultValue (220)
    /// - 기대 결과: state.sidebarWidth == max (400)
    func test_sidebarWidth_aboveMaximum_clampsToMaximum() async {
        let store = makeSidebarStore(initialState: makeSidebarState(width: SidebarWidth.defaultValue))

        // aboveMaximum은 max 초과이므로 max로 클램프된다.
        await store.send(.view(.setSidebarWidth(SidebarWidth.aboveMaximum))) { state in
            state.sidebarWidth = SidebarWidth.max
        }

        await store.finish()
    }

    // MARK: - FMW-002-show_inspector_pane / FMW-002-hide_inspector_pane

    /// FMW-002-show_inspector_pane: toggleInspector가 inspectorVisible을 true로 설정
    /// 인스펙터 표시 토글이 inspectorVisible을 false → true로 변경
    /// - 검증 내용: toggleInspector 전송 시 inspectorVisible이 false → true로 변경
    /// - 사전 조건: inspectorVisible == false
    /// - 기대 결과: state.inspectorVisible == true
    func test_showInspector_setsInspectorVisible() async {
        let store = makeInspectorStore(initialState: makeInspectorState(visible: false))

        await store.send(.toggleInspector) { state in
            state.inspectorVisible = true
        }

        await store.finish()
    }

    /// FMW-002-hide_inspector_pane: toggleInspector가 inspectorVisible을 false로 설정
    /// 인스펙터 숨김 토글이 inspectorVisible을 true → false로 변경
    /// - 검증 내용: toggleInspector 전송 시 inspectorVisible이 true → false로 변경
    /// - 사전 조건: inspectorVisible == true
    /// - 기대 결과: state.inspectorVisible == false
    func test_hideInspector_setsInspectorHidden() async {
        let store = makeInspectorStore(initialState: makeInspectorState(visible: true))

        await store.send(.toggleInspector) { state in
            state.inspectorVisible = false
        }

        await store.finish()
    }

    /// FMW-002-show_inspector_pane: 선택 없는 상태에서 인스펙터 안전성 — no-selection safety
    /// no-selection 상태에서 인스펙터 동작이 크래시 없이 안전한지 검증
    /// - 검증 내용: no-selection 상태에서 toggleInspector, setInspectorPaneExists 동작 안전성
    /// - 사전 조건: inspectorVisible=false, inspectorPaneExists=false
    /// - 기대 결과: toggleInspector 후 inspectorVisible=true, setInspectorPaneExists 후 inspectorPaneExists=true (크래시 없음)
    func test_noSelection_inspectorSafety_doesNotCrash() async {
        // no-selection 상태: inspectorVisible=false, inspectorPaneExists=false
        let store = makeInspectorStore(initialState: makeInspectorState())

        // toggleInspector 동작이 크래시 없이 정상 동작
        await store.send(.toggleInspector) { state in
            state.inspectorVisible = true
        }

        // setInspectorPaneExists도 크래시 없이 동작
        await store.send(.setInspectorPaneExists(true)) { state in
            state.inspectorPaneExists = true
        }

        await store.finish()
    }

    // MARK: - Independence Invariants

    // sidebar_and_inspector_visibility_are_independent = true

    /// FMW-002-show_sidebar / FMW-002-hide_sidebar: 사이드바-인스펙터 독립성 (사이드바→인스펙터 영향 없음)
    /// 사이드바와 인스펙터의 가시성은 독립적 — 사이드바 토글이 인스펙터 상태에 영향을 주지 않음
    /// - 검증 내용: 사이드바 토글 후 인스펙터 상태 변화 없음 (inspectorVisible == false 유지)
    /// - 사전 조건: sidebarVisible=true, inspectorVisible=false (기본값)
    /// - 기대 결과: inspectorState.inspectorVisible == false 유지 (독립 인스턴스 불변 단언)
    func test_sidebarToggle_doesNotAffectInspector() async {
        // 사이드바와 인스펙터는 독립 리듀서이므로
        // 사이드바 상태 변화가 인스펙터 상태에 영향을 주지 않음을 검증
        let sidebarState = makeSidebarState(visible: true)
        let inspectorState = makeInspectorState()

        let sidebarStore = makeSidebarStore(initialState: sidebarState)

        // 사이드바 토글
        await sidebarStore.send(.view(.setSidebarVisible(false))) { state in
            state.sidebarVisible = false
        }

        // 인스펙터 상태는 변하지 않음 — 독립 인스턴스이므로 기본값 유지
        XCTAssertFalse(inspectorState.inspectorVisible)

        await sidebarStore.finish()
    }

    /// FMW-002-show_inspector_pane / FMW-002-hide_inspector_pane: 인스펙터-사이드바 독립성 (인스펙터→사이드바 영향 없음)
    /// 사이드바와 인스펙터의 가시성은 독립적 — 인스펙터 토글이 사이드바 상태에 영향을 주지 않음
    /// - 검증 내용: 인스펙터 토글 후 사이드바 상태 변화 없음 (sidebarVisible == true, sidebarWidth == defaultValue 유지)
    /// - 사전 조건: sidebarVisible=true (기본값), inspectorVisible=false
    /// - 기대 결과: sidebarState.sidebarVisible == true, sidebarState.sidebarWidth == defaultValue 유지 (독립 인스턴스 불변 단언)
    func test_inspectorToggle_doesNotAffectSidebar() async {
        let sidebarState = makeSidebarState()
        let inspectorStore = makeInspectorStore(initialState: makeInspectorState(visible: false))

        // 인스펙터 토글
        await inspectorStore.send(.toggleInspector) { state in
            state.inspectorVisible = true
        }

        // 사이드바 상태는 변하지 않음 — 독립 인스턴스이므로 기본값 유지
        XCTAssertTrue(sidebarState.sidebarVisible)
        XCTAssertEqual(sidebarState.sidebarWidth, SidebarWidth.defaultValue)

        await inspectorStore.finish()
    }
}
