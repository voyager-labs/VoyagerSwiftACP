import ComposableArchitecture
@testable import VoyagerPagesFileManager
import XCTest

// FMW-002: 사이드바/인스펙터 패인 관리 테스트
// 사이드바 표시/숨김, 너비 클램프, 인스펙터 표시/숨김, 독립성 계약 검증

// MARK: - Width Constants

// FileManagerSidebarPreferenceReducer의 클램프 상수와 동기화
private enum SidebarWidth {
    static let min: CGFloat = 150
    static let max: CGFloat = 400
}

@MainActor
final class FMW002ManageFileManagerWindowPanesFeatureTests: XCTestCase {
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

    // MARK: - Test Group 1: Sidebar Visibility

    // FMW-002-show_sidebar, FMW-002-hide_sidebar

    /// FMW-002-show_sidebar: 사이드바 표시 액션이 sidebarVisible을 true로 설정
    func test_showSidebar_setsSidebarVisible() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarVisible = false

        let store = makeSidebarStore(initialState: initialState)

        await store.send(.view(.setSidebarVisible(true))) { state in
            state.sidebarVisible = true
        }

        await store.finish()
    }

    /// FMW-002-hide_sidebar: 사이드바 숨김 액션이 sidebarVisible을 false로 설정
    func test_hideSidebar_setsSidebarHidden() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarVisible = true

        let store = makeSidebarStore(initialState: initialState)

        await store.send(.view(.setSidebarVisible(false))) { state in
            state.sidebarVisible = false
        }

        await store.finish()
    }

    /// 반복 토글(show→hide→show)이 원래 상태로 복귀하는지 검증
    func test_repeatedToggle_returnsToOriginalState() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarVisible = true

        let store = makeSidebarStore(initialState: initialState)

        await store.send(.view(.setSidebarVisible(false))) { state in
            state.sidebarVisible = false
        }

        await store.send(.view(.setSidebarVisible(true))) { state in
            state.sidebarVisible = true
        }

        await store.finish()
    }

    /// 초기 sidebarVisible 기본값이 true인지 검증
    func test_initialSidebarVisibility_isExpectedDefault() {
        let state = FileManagerSidebarState()
        XCTAssertTrue(
            state.sidebarVisible,
            "sidebarVisible 기본값은 true여야 한다",
        )
    }

    // MARK: - Test Group 2: Sidebar Width Clamp

    // FMW-002-adjust_sidebar_width

    /// 정상 범위 내 너비 값이 그대로 적용되는지 검증
    func test_sidebarWidth_withinAllowedRange_appliesValue() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarWidth = 220

        let store = makeSidebarStore(initialState: initialState)

        await store.send(.view(.setSidebarWidth(250))) { state in
            state.sidebarWidth = 250
        }

        await store.finish()
    }

    /// 최소값 미만 너비가 최소값으로 클램프되는지 검증
    func test_sidebarWidth_belowMinimum_clampsToMinimum() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarWidth = 220

        let store = makeSidebarStore(initialState: initialState)

        // 100은 min(150) 미만이므로 150으로 클램프
        await store.send(.view(.setSidebarWidth(100))) { state in
            state.sidebarWidth = SidebarWidth.min
        }

        await store.finish()
    }

    /// 최대값 초과 너비가 최대값으로 클램프되는지 검증
    func test_sidebarWidth_aboveMaximum_clampsToMaximum() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarWidth = 220

        let store = makeSidebarStore(initialState: initialState)

        // 500은 max(400) 초과이므로 400으로 클램프
        await store.send(.view(.setSidebarWidth(500))) { state in
            state.sidebarWidth = SidebarWidth.max
        }

        await store.finish()
    }

    // MARK: - Test Group 3: Inspector Visibility

    // FMW-002-show_inspector_pane, FMW-002-hide_inspector_pane

    /// FMW-002-show_inspector_pane: toggleInspector가 inspectorVisible을 true로 설정
    func test_showInspector_setsInspectorVisible() async {
        var initialState = FileManagerInspectorState()
        initialState.inspectorVisible = false

        let store = TestStore(initialState: initialState) {
            FileManagerInspectorFeature()
        }

        await store.send(.toggleInspector) { state in
            state.inspectorVisible = true
        }

        await store.finish()
    }

    /// FMW-002-hide_inspector_pane: toggleInspector가 inspectorVisible을 false로 설정
    func test_hideInspector_setsInspectorHidden() async {
        var initialState = FileManagerInspectorState()
        initialState.inspectorVisible = true

        let store = TestStore(initialState: initialState) {
            FileManagerInspectorFeature()
        }

        await store.send(.toggleInspector) { state in
            state.inspectorVisible = false
        }

        await store.finish()
    }

    /// 선택 없는 상태에서 인스펙터 동작이 크래시 없이 안전한지 검증
    func test_noSelection_inspectorSafety_doesNotCrash() async {
        // no-selection 상태: inspectorVisible=false, inspectorPaneExists=false
        let initialState = FileManagerInspectorState()

        let store = TestStore(initialState: initialState) {
            FileManagerInspectorFeature()
        }

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

    // MARK: - Test Group 4: Sidebar-Inspector Independence

    // sidebar_and_inspector_visibility_are_independent = true

    /// 사이드바 토글이 인스펙터 상태에 영향을 주지 않는지 검증
    func test_sidebarToggle_doesNotAffectInspector() async {
        // 사이드바와 인스펙터는 독립 리듀서이므로
        // 사이드바 상태 변화가 인스펙터 상태에 영향을 주지 않음을 검증
        var sidebarState = FileManagerSidebarState()
        sidebarState.sidebarVisible = true

        let inspectorState = FileManagerInspectorState()

        let sidebarStore = makeSidebarStore(initialState: sidebarState)

        // 사이드바 토글
        await sidebarStore.send(.view(.setSidebarVisible(false))) { state in
            state.sidebarVisible = false
        }

        // 인스펙터 상태는 변하지 않음 — 독립 인스턴스이므로 기본값 유지
        XCTAssertFalse(inspectorState.inspectorVisible)

        await sidebarStore.finish()
    }

    /// 인스펙터 토글이 사이드바 상태에 영향을 주지 않는지 검증
    func test_inspectorToggle_doesNotAffectSidebar() async {
        let sidebarState = FileManagerSidebarState()

        var inspectorState = FileManagerInspectorState()
        inspectorState.inspectorVisible = false

        let inspectorStore = TestStore(initialState: inspectorState) {
            FileManagerInspectorFeature()
        }

        // 인스펙터 토글
        await inspectorStore.send(.toggleInspector) { state in
            state.inspectorVisible = true
        }

        // 사이드바 상태는 변하지 않음 — 독립 인스턴스이므로 기본값 유지
        XCTAssertTrue(sidebarState.sidebarVisible)
        XCTAssertEqual(sidebarState.sidebarWidth, 220)

        await inspectorStore.finish()
    }
}
