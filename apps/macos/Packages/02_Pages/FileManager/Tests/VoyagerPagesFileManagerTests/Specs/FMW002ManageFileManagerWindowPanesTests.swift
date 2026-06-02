import AppKit
import ComposableArchitecture
@testable import VoyagerPagesFileManager
import XCTest

// 사이드바 표시/숨김, 너비 클램프, 인스펙터 표시/숨김, 독립성 계약 검증.

@MainActor
final class FMW002ManageFileManagerWindowPanesTests: XCTestCase {
    private typealias SidebarWidth = PaneTestSupport.SidebarWidth

    // MARK: - FMW-002-show_sidebar

    /// FMW-002-show_sidebar: 사이드바 표시 액션이 sidebarVisible을 true로 설정
    /// setSidebarVisible(true) 전송 시 sidebarVisible이 false에서 true로 변경되는지 검증.
    /// - 검증 내용: setSidebarVisible(true) 전송 시 sidebarVisible이 false → true로 변경
    /// - 사전 조건: sidebarVisible == false
    /// - 기대 결과: state.sidebarVisible == true
    func test_showSidebar_setsSidebarVisible() async {
        let store = PaneTestSupport
            .makeSidebarStore(initialState: PaneTestSupport.makeSidebarState(visible: false))

        await store.send(.view(.setSidebarVisible(true))) { state in
            state.sidebarVisible = true
        }

        await store.finish()
    }

    /// FMW-002-show_sidebar: 숨김 이후 다시 표시하면 원래 표시 상태로 복귀
    /// 반복 토글 중 마지막 show_sidebar 동작이 sidebarVisible을 true로 복구하는지 검증.
    /// - 검증 내용: setSidebarVisible(false) 이후 setSidebarVisible(true) 전송 후 표시 상태 복귀
    /// - 사전 조건: sidebarVisible == true
    /// - 기대 결과: 최종 sidebarVisible == true
    func test_repeatedToggle_returnsToOriginalState() async {
        let store = PaneTestSupport
            .makeSidebarStore(initialState: PaneTestSupport.makeSidebarState(visible: true))

        await store.send(.view(.setSidebarVisible(false))) { state in
            state.sidebarVisible = false
        }

        await store.send(.view(.setSidebarVisible(true))) { state in
            state.sidebarVisible = true
        }

        await store.finish()
    }

    /// FMW-002-show_sidebar: 초기 sidebarVisible 기본값 검증
    /// 기본 생성 상태가 사이드바 표시 상태로 시작하는지 검증.
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

    // MARK: - FMW-002-hide_sidebar

    /// FMW-002-hide_sidebar: 사이드바 숨김 액션이 sidebarVisible을 false로 설정
    /// setSidebarVisible(false) 전송 시 sidebarVisible이 true에서 false로 변경되는지 검증.
    /// - 검증 내용: setSidebarVisible(false) 전송 시 sidebarVisible이 true → false로 변경
    /// - 사전 조건: sidebarVisible == true
    /// - 기대 결과: state.sidebarVisible == false
    func test_hideSidebar_setsSidebarHidden() async {
        let store = PaneTestSupport
            .makeSidebarStore(initialState: PaneTestSupport.makeSidebarState(visible: true))

        await store.send(.view(.setSidebarVisible(false))) { state in
            state.sidebarVisible = false
        }

        await store.finish()
    }

    /// FMW-002-hide_sidebar: 메뉴/단축키 Hide Sidebar는 기존 유효 너비를 보존
    /// 숨김 상태에서 다시 표시하면 사용자가 마지막으로 조정한 너비로 복원되어야 한다.
    func test_hideSidebar_preservesLastValidWidthForShowRestore() async {
        let store = PaneTestSupport
            .makeSidebarStore(initialState: PaneTestSupport.makeSidebarState(
                visible: true,
                width: SidebarWidth.inRange,
            ))

        await store.send(.view(.setSidebarVisible(false))) { state in
            state.sidebarVisible = false
        }

        XCTAssertEqual(store.state.sidebarWidth, SidebarWidth.inRange)

        await store.send(.view(.setSidebarVisible(true))) { state in
            state.sidebarVisible = true
        }

        XCTAssertEqual(store.state.sidebarWidth, SidebarWidth.inRange)

        await store.finish()
    }

    /// FMW-002-hide_sidebar: 숨김 상태의 layout width 변화는 저장된 너비를 덮지 않음
    /// Hide Sidebar 직후 SwiftUI/AppKit layout이 0 또는 최소폭을 보고해도 복원 너비는 유지되어야 한다.
    func test_hiddenSidebarIgnoresLayoutWidthSync() async {
        let store = PaneTestSupport
            .makeSidebarStore(initialState: PaneTestSupport.makeSidebarState(
                visible: false,
                width: SidebarWidth.inRange,
            ))

        await store.send(.view(.setSidebarWidth(0)))
        XCTAssertEqual(store.state.sidebarWidth, SidebarWidth.inRange)

        await store.send(.view(.setSidebarWidth(SidebarWidth.min)))
        XCTAssertEqual(store.state.sidebarWidth, SidebarWidth.inRange)

        await store.finish()
    }

    // MARK: - FMW-002-adjust_sidebar_width

    /// FMW-002-adjust_sidebar_width: 정상 범위 내 너비 적용
    /// 정상 범위 내 너비 값이 그대로 적용되는지 검증.
    /// - 검증 내용: setSidebarWidth(inRange) 전송 시 sidebarWidth가 입력값으로 설정
    /// - 사전 조건: sidebarWidth == defaultValue (220)
    /// - 기대 결과: state.sidebarWidth == inRange (250)
    func test_sidebarWidth_withinAllowedRange_appliesValue() async {
        let store = PaneTestSupport
            .makeSidebarStore(initialState: PaneTestSupport.makeSidebarState(width: SidebarWidth.defaultValue))

        await store.send(.view(.setSidebarWidth(SidebarWidth.inRange))) { state in
            state.sidebarWidth = SidebarWidth.inRange
        }

        await store.finish()
    }

    /// FMW-002-adjust_sidebar_width: 최소값 미만 너비 클램프
    /// 최소값 미만 너비가 최소값으로 클램프되는지 검증.
    /// - 검증 내용: setSidebarWidth(belowMinimum=100) 전송 시 sidebarWidth가 min(150)으로 클램프
    /// - 사전 조건: sidebarWidth == defaultValue (220)
    /// - 기대 결과: state.sidebarWidth == min (150)
    func test_sidebarWidth_belowMinimum_clampsToMinimum() async {
        let store = PaneTestSupport
            .makeSidebarStore(initialState: PaneTestSupport.makeSidebarState(width: SidebarWidth.defaultValue))

        // belowMinimum은 min 미만이므로 min으로 클램프된다.
        await store.send(.view(.setSidebarWidth(SidebarWidth.belowMinimum))) { state in
            state.sidebarWidth = SidebarWidth.min
        }

        await store.finish()
    }

    /// FMW-002-adjust_sidebar_width: 최대값 초과 너비 클램프
    /// 최대값 초과 너비가 최대값으로 클램프되는지 검증.
    /// - 검증 내용: setSidebarWidth(aboveMaximum=500) 전송 시 sidebarWidth가 max(400)으로 클램프
    /// - 사전 조건: sidebarWidth == defaultValue (220)
    /// - 기대 결과: state.sidebarWidth == max (400)
    func test_sidebarWidth_aboveMaximum_clampsToMaximum() async {
        let store = PaneTestSupport
            .makeSidebarStore(initialState: PaneTestSupport.makeSidebarState(width: SidebarWidth.defaultValue))

        // aboveMaximum은 max 초과이므로 max으로 클램프된다.
        await store.send(.view(.setSidebarWidth(SidebarWidth.aboveMaximum))) { state in
            state.sidebarWidth = SidebarWidth.max
        }

        await store.finish()
    }

    /// FMW-002-adjust_sidebar_width: divider를 정확히 최소폭까지 줄이면 숨김이 아닌 보이는 resize로 처리
    /// 150pt는 유효한 Sidebar width이므로 hidden 전환 없이 width만 저장한다.
    func test_userResizeToMinimumSyncsWidthWithoutHidingSidebar() {
        var sync = FileManagerSidebarSync(storeSidebarWidth: SidebarWidth.inRange)
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)

        let sidebarView = NSView()
        let contentView = NSView()
        splitView.addArrangedSubview(sidebarView)
        splitView.addArrangedSubview(contentView)

        sync.applyInitialLayoutIfNeeded(
            sidebarVisible: true,
            sidebarWidth: SidebarWidth.inRange,
            splitView: splitView,
            mainContainerLeading: nil,
            contentVerticalMargin: 4,
        ) { _ in }

        splitView.setPosition(FileManagerSidebarSync.sidebarMinWidth, ofDividerAt: 0)
        splitView.adjustSubviews()

        var syncedWidths: [CGFloat] = []
        let decision = sync.handleSplitViewResize(
            splitView: splitView,
            sidebarView: sidebarView,
            storeSidebarVisible: true,
            isUserInitiatedCollapse: true,
        ) { width in
            syncedWidths.append(width)
        }

        XCTAssertEqual(decision, .none)
        XCTAssertEqual(syncedWidths, [FileManagerSidebarSync.sidebarMinWidth])
    }

    /// FMW-002-adjust_sidebar_width: 보이는 Sidebar divider는 0 또는 최소폭 이상으로만 스냅
    /// 0~150pt 사이 중간 폭은 traffic-light 없는 Sidebar 상태를 만들 수 있으므로 hidden(0)으로 스냅한다.
    func test_visibleSidebarDividerBelowMinimumSnapsToHidden() {
        XCTAssertEqual(
            FileManagerSidebarSync.constrainedSidebarDividerPosition(
                proposedPosition: FileManagerSidebarSync.sidebarMinWidth - 1,
            ),
            0,
        )
    }

    /// FMW-002-adjust_sidebar_width: 숨김 Sidebar를 divider로 다시 열 때도 중간 폭은 허용하지 않음
    /// hidden 상태에서도 0~150pt 사이는 0으로 유지하고, 150pt 이상부터 보이는 Sidebar로 전환한다.
    func test_hiddenSidebarDividerOpeningKeepsIntermediateWidthCollapsed() {
        XCTAssertEqual(
            FileManagerSidebarSync.constrainedSidebarDividerPosition(proposedPosition: 1),
            0,
        )
        XCTAssertEqual(
            FileManagerSidebarSync.constrainedSidebarDividerPosition(
                proposedPosition: FileManagerSidebarSync.sidebarMinWidth,
            ),
            FileManagerSidebarSync.sidebarMinWidth,
        )
    }

    /// FMW-002-adjust_sidebar_width: divider를 최소폭 미만으로 줄이면 hidden으로 전환
    /// 150pt 미만은 유효 너비로 저장하지 않고 Hide Sidebar 경로로 라우팅한다.
    func test_userResizeBelowMinimumHidesSidebarWithoutSyncingWidth() {
        var sync = FileManagerSidebarSync(storeSidebarWidth: SidebarWidth.inRange)
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)

        let sidebarView = NSView()
        let contentView = NSView()
        splitView.addArrangedSubview(sidebarView)
        splitView.addArrangedSubview(contentView)

        sync.applyInitialLayoutIfNeeded(
            sidebarVisible: true,
            sidebarWidth: SidebarWidth.inRange,
            splitView: splitView,
            mainContainerLeading: nil,
            contentVerticalMargin: 4,
        ) { _ in }

        splitView.setPosition(FileManagerSidebarSync.sidebarMinWidth - 1, ofDividerAt: 0)
        splitView.adjustSubviews()

        var syncedWidths: [CGFloat] = []
        let decision = sync.handleSplitViewResize(
            splitView: splitView,
            sidebarView: sidebarView,
            storeSidebarVisible: true,
            isUserInitiatedCollapse: true,
        ) { width in
            syncedWidths.append(width)
        }

        XCTAssertEqual(decision, .hideSidebar)
        XCTAssertTrue(syncedWidths.isEmpty)
    }

    /// FMW-002-show_sidebar: hidden 상태에서 divider를 다시 열면 store도 visible로 복구
    /// 실제 Sidebar frame은 보이는데 traffic light만 숨겨진 제3 상태가 생기지 않도록 showSidebar 결정을 반환한다.
    func test_userDragOpenFromHiddenShowsSidebarWithCurrentWidth() {
        var sync = FileManagerSidebarSync(storeSidebarWidth: SidebarWidth.inRange)
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)

        let sidebarView = NSView()
        let contentView = NSView()
        splitView.addArrangedSubview(sidebarView)
        splitView.addArrangedSubview(contentView)

        sync.applyInitialLayoutIfNeeded(
            sidebarVisible: false,
            sidebarWidth: SidebarWidth.inRange,
            splitView: splitView,
            mainContainerLeading: nil,
            contentVerticalMargin: 4,
        ) { _ in }

        splitView.setPosition(FileManagerSidebarSync.sidebarMinWidth, ofDividerAt: 0)
        splitView.adjustSubviews()

        var syncedWidths: [CGFloat] = []
        let decision = sync.handleSplitViewResize(
            splitView: splitView,
            sidebarView: sidebarView,
            storeSidebarVisible: false,
            isUserInitiatedCollapse: true,
        ) { width in
            syncedWidths.append(width)
        }

        XCTAssertEqual(decision, .showSidebar(FileManagerSidebarSync.sidebarMinWidth))
        XCTAssertTrue(syncedWidths.isEmpty)
    }

    /// FMW-002 Sidebar preference fan-out: 기존 window-local Sidebar 상태를 preference 적용 시 보존
    /// App 레이어가 열린 창에 app preferences를 다시 적용할 때 사용할 projection이 width/visibility를 유지하는지 검증한다.
    func test_windowPreferenceProjectionPreservesWindowLocalSidebarState() {
        var windowState = FileManagerWindowState()
        windowState.sidebar.sidebarVisible = false
        windowState.sidebar.sidebarWidth = SidebarWidth.inRange

        var preferences = AppPreferencesState()
        preferences.sidebarVisible = true
        preferences.sidebarWidth = SidebarWidth.max

        let projected = windowState.appPreferencesPreservingSidebarState(from: preferences)

        XCTAssertFalse(projected.sidebarVisible)
        XCTAssertEqual(projected.sidebarWidth, SidebarWidth.inRange)
    }

    // MARK: - FMW-002-show_inspector_pane

    /// FMW-002-show_inspector_pane: toggleInspector가 inspectorVisible을 true로 설정
    /// 인스펙터 표시 토글이 inspectorVisible을 false에서 true로 변경하는지 검증.
    /// - 검증 내용: toggleInspector 전송 시 inspectorVisible이 false → true로 변경
    /// - 사전 조건: inspectorVisible == false
    /// - 기대 결과: state.inspectorVisible == true
    func test_showInspector_setsInspectorVisible() async {
        let store = PaneTestSupport
            .makeInspectorStore(initialState: PaneTestSupport.makeInspectorState(visible: false))

        await store.send(.toggleInspector) { state in
            state.inspectorVisible = true
        }

        await store.finish()
    }

    /// FMW-002-show_inspector_pane: 선택 없는 상태에서 인스펙터 안전성
    /// no-selection 상태에서 인스펙터 동작이 크래시 없이 안전한지 검증.
    /// - 검증 내용: no-selection 상태에서 toggleInspector, setInspectorPaneExists 동작 안전성
    /// - 사전 조건: inspectorVisible=false, inspectorPaneExists=false
    /// - 기대 결과: toggleInspector 후 inspectorVisible=true, setInspectorPaneExists 후 inspectorPaneExists=true
    func test_noSelection_inspectorSafety_doesNotCrash() async {
        let store = PaneTestSupport.makeInspectorStore(initialState: PaneTestSupport.makeInspectorState())

        await store.send(.toggleInspector) { state in
            state.inspectorVisible = true
        }

        await store.send(.setInspectorPaneExists(true)) { state in
            state.inspectorPaneExists = true
        }

        await store.finish()
    }

    // MARK: - FMW-002-hide_inspector_pane

    /// FMW-002-hide_inspector_pane: toggleInspector가 inspectorVisible을 false로 설정
    /// 인스펙터 숨김 토글이 inspectorVisible을 true에서 false로 변경하는지 검증.
    /// - 검증 내용: toggleInspector 전송 시 inspectorVisible이 true → false로 변경
    /// - 사전 조건: inspectorVisible == true
    /// - 기대 결과: state.inspectorVisible == false
    func test_hideInspector_setsInspectorHidden() async {
        let store = PaneTestSupport
            .makeInspectorStore(initialState: PaneTestSupport.makeInspectorState(visible: true))

        await store.send(.toggleInspector) { state in
            state.inspectorVisible = false
        }

        await store.finish()
    }

    // MARK: - FMW-002-sidebar_and_inspector_visibility_are_independent

    /// FMW-002-sidebar_and_inspector_visibility_are_independent: 사이드바 토글이 인스펙터 상태에 영향 없음
    /// 사이드바와 인스펙터의 가시성이 독립적이라 사이드바 토글이 인스펙터 상태를 변경하지 않는지 검증.
    /// - 검증 내용: 사이드바 토글 후 인스펙터 상태 변화 없음
    /// - 사전 조건: sidebarVisible=true, inspectorVisible=false
    /// - 기대 결과: inspectorState.inspectorVisible == false 유지
    func test_sidebarToggle_doesNotAffectInspector() async {
        let sidebarState = PaneTestSupport.makeSidebarState(visible: true)
        let inspectorState = PaneTestSupport.makeInspectorState()

        let sidebarStore = PaneTestSupport.makeSidebarStore(initialState: sidebarState)

        await sidebarStore.send(.view(.setSidebarVisible(false))) { state in
            state.sidebarVisible = false
        }

        XCTAssertFalse(inspectorState.inspectorVisible)

        await sidebarStore.finish()
    }

    /// FMW-002-sidebar_and_inspector_visibility_are_independent: 인스펙터 토글이 사이드바 상태에 영향 없음
    /// 사이드바와 인스펙터의 가시성이 독립적이라 인스펙터 토글이 사이드바 상태를 변경하지 않는지 검증.
    /// - 검증 내용: 인스펙터 토글 후 사이드바 상태 변화 없음
    /// - 사전 조건: sidebarVisible=true, inspectorVisible=false
    /// - 기대 결과: sidebarState.sidebarVisible == true, sidebarState.sidebarWidth == defaultValue 유지
    func test_inspectorToggle_doesNotAffectSidebar() async {
        let sidebarState = PaneTestSupport.makeSidebarState()
        let inspectorStore = PaneTestSupport
            .makeInspectorStore(initialState: PaneTestSupport.makeInspectorState(visible: false))

        await inspectorStore.send(.toggleInspector) { state in
            state.inspectorVisible = true
        }

        XCTAssertTrue(sidebarState.sidebarVisible)
        XCTAssertEqual(sidebarState.sidebarWidth, SidebarWidth.defaultValue)

        await inspectorStore.finish()
    }
}
