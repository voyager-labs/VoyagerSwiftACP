import AppKit
import ComposableArchitecture
import Foundation
import PerceptionCore
import SwiftUI
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

extension CTM004SwitchContentTabWithUsedContentTabsSwitcherTests {
    // MARK: - CTM-004-confirm_content_tab_switcher_selection

    /// CTM-004-confirm_content_tab_switcher_selection: focused window command가 focused non-current 후보를 활성화한다.
    /// Control release 등의 focused window command가 소유 presentation을 닫고 정확히 한 번 canonical activation으로 setCurrent를
    /// 방출하는지 검증한다.
    /// - 검증 내용: focused live candidate를 가진 presentation에서 `.request(.activateContentTabSwitcherSelection)`,
    /// presentation nil 전환, `.contentTabs(.setCurrent(id))` 단일 effect
    /// - 사전 조건: automatic presentation과 current가 아닌 live focused candidate
    /// - 기대 결과: presentation은 닫히고 target ID를 가진 setCurrent action 하나만 수신된다.
    @MainActor
    func testFocusedWindowCommandActivatesFocusedNonCurrentCandidateExactlyOnce() async {
        var state = makeSwitcherWindowState(prefix: "confirm-valid")
        let targetID = id("confirm-valid-A")
        let previousActiveTabID = id("confirm-valid-previous")
        state.contentTabs.previousActiveTabID = previousActiveTabID
        state.contentTabSwitcherPresentation = .init(
            source: .automatic,
            candidateIDs: ids("confirm-valid-B", "confirm-valid-A"),
            focusedCandidateID: targetID,
        )
        let semanticSnapshot = ContentTabSemanticSnapshot(state)
        let store = TestStore(initialState: state) {
            FileManagerWindowCommandRoutingReducer()
        }

        await store.send(.request(.activateContentTabSwitcherSelection)) {
            $0.contentTabSwitcherPresentation = nil
        }
        await store.receive(\.contentTabs.setCurrent, targetID)
        await store.finish()

        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), semanticSnapshot)
        XCTAssertEqual(store.state.contentTabs.previousActiveTabID, previousActiveTabID)
    }

    /// CTM-004-confirm_content_tab_switcher_selection: 클릭한 후보가 focused 후보와 달라도 클릭 대상을 확정한다.
    /// 후보 Button의 explicit ID가 기존 focused ID 대신 canonical activation helper로 전달되는지 검증한다.
    /// - 검증 내용: explicit clicked ID 확인, presentation nil 전환, clicked ID의 setCurrent 단일 effect
    /// - 사전 조건: focused 후보 B와 별도의 live clicked 후보 A를 가진 automatic presentation
    /// - 기대 결과: presentation은 닫히고 clicked 후보 A를 가진 setCurrent action 하나만 수신된다.
    @MainActor
    func testClickedCandidateActivatesExplicitIDAndClosesExactlyOnce() async {
        var state = makeSwitcherWindowState(prefix: "activate-clicked")
        let focusedID = id("activate-clicked-B")
        let clickedID = id("activate-clicked-A")
        state.contentTabSwitcherPresentation = .init(
            source: .automatic,
            candidateIDs: [focusedID, clickedID],
            focusedCandidateID: focusedID,
        )
        let semanticSnapshot = ContentTabSemanticSnapshot(state)
        let store = TestStore(initialState: state) {
            FileManagerWindowCommandRoutingReducer()
        }

        await store.send(.view(.activateContentTabSwitcherCandidate(clickedID))) {
            $0.contentTabSwitcherPresentation = nil
        }
        await store.receive(\.contentTabs.setCurrent, clickedID)
        await store.finish()

        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), semanticSnapshot)
    }

    /// CTM-004-confirm_content_tab_switcher_selection: 현재 후보를 explicit ID로 다시 활성화하면 overlay만 닫는다.
    /// same-current explicit-ID activation이 ContentTabFeature.setCurrent의 history mutation을 우회하는지 검증한다.
    /// - 검증 내용: current candidate explicit ID 활성화, presentation nil 전환, effect 부재, 이전 active ID 보존
    /// - 사전 조건: active candidate와 별도 previousActiveTabID를 가진 automatic presentation
    /// - 기대 결과: presentation만 nil이 되고 semantic snapshot과 previousActiveTabID가 유지된다.
    @MainActor
    func testActivateSameCurrentExplicitIDClosesWithoutEffectOrMutation() async {
        var state = makeSwitcherWindowState(prefix: "confirm-current")
        let currentID = id("confirm-current-B")
        let previousActiveTabID = id("confirm-current-A")
        state.contentTabs.previousActiveTabID = previousActiveTabID
        state.contentTabSwitcherPresentation = .init(
            source: .automatic,
            candidateIDs: ids("confirm-current-B", "confirm-current-A"),
            focusedCandidateID: currentID,
        )
        let semanticSnapshot = ContentTabSemanticSnapshot(state)
        let store = TestStore(initialState: state) {
            FileManagerWindowCommandRoutingReducer()
        }

        await store.send(.view(.activateContentTabSwitcherCandidate(currentID))) {
            $0.contentTabSwitcherPresentation = nil
        }
        await store.finish()

        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), semanticSnapshot)
        XCTAssertEqual(store.state.contentTabs.previousActiveTabID, previousActiveTabID)
    }

    /// CTM-004-confirm_content_tab_switcher_selection: focus·후보·source·status·window eligibility가 invalid이면 두
    /// activation
    /// seam 모두 no-op이다.
    /// explicit-ID activation과 missing/stale focused window command가 활성화 시점의 live projection과 window admission을 다시
    /// 검증해 stale 입력이 presentation과 semantic state를 훼손하지 않는지 확인한다.
    /// - 검증 내용: nil/stale focused window command, explicit stale/non-live ID, noninteractive source,
    /// loading/empty/error
    /// status, interaction-ineligible window
    /// - 사전 조건: 각 invalid presentation/state 조합에 독립적인 FileManagerWindowCommandRoutingReducer store
    /// - 기대 결과: 모든 조합에서 presentation과 ContentTabSemanticSnapshot이 그대로 유지되고 effect가 없다.
    @MainActor
    func testActivateInvalidPresentationAndCandidateStatesPreserveStateWithoutEffect() async {
        var nilFocus = makeSwitcherWindowState(prefix: "confirm-nil-focus")
        nilFocus.contentTabSwitcherPresentation = .init(
            source: .automatic,
            candidateIDs: ids("confirm-nil-focus-B", "confirm-nil-focus-A"),
            focusedCandidateID: nil,
        )

        var staleFocus = makeSwitcherWindowState(prefix: "confirm-stale-focus")
        staleFocus.contentTabSwitcherPresentation = .init(
            source: .automatic,
            candidateIDs: ids("confirm-stale-focus-B", "confirm-stale-focus-A"),
            focusedCandidateID: id("confirm-stale-focus-missing"),
        )

        var missingTab = makeSwitcherWindowState(prefix: "confirm-missing-tab")
        missingTab.contentTabSwitcherPresentation = .init(
            source: .automatic,
            candidateIDs: [id("confirm-missing-tab-missing")],
            focusedCandidateID: id("confirm-missing-tab-missing"),
        )

        var loading = makeSwitcherWindowState(prefix: "confirm-loading")
        loading.contentTabSwitcherPresentation = .init(
            source: .loading,
            candidateIDs: ids("confirm-loading-B", "confirm-loading-A"),
            focusedCandidateID: id("confirm-loading-A"),
        )

        var empty = makeSwitcherWindowState(prefix: "confirm-empty")
        empty.contentTabs = ContentTabState(tabs: [], activeTabID: nil, recentlyUsedTabIDs: [])
        empty.contentTabSwitcherPresentation = .init(source: .automatic)

        var error = makeSwitcherWindowState(prefix: "confirm-error")
        error.contentTabSwitcherPresentation = .init(
            source: .error(message: "Unable to load recent tabs."),
            candidateIDs: ids("confirm-error-B", "confirm-error-A"),
            focusedCandidateID: id("confirm-error-A"),
        )

        var ineligibleWindow = makeSwitcherWindowState(prefix: "confirm-ineligible")
        ineligibleWindow.isClosing = true
        ineligibleWindow.contentTabSwitcherPresentation = .init(
            source: .automatic,
            candidateIDs: ids("confirm-ineligible-B", "confirm-ineligible-A"),
            focusedCandidateID: id("confirm-ineligible-A"),
        )

        let scenarios: [(String, FileManagerWindowState, FileManagerWindowAction)] = [
            ("nil-focused-window-command", nilFocus, .request(.activateContentTabSwitcherSelection)),
            ("stale-focused-window-command", staleFocus, .request(.activateContentTabSwitcherSelection)),
            (
                "missing-tab-explicit-id",
                missingTab,
                .view(.activateContentTabSwitcherCandidate(id("confirm-missing-tab-missing"))),
            ),
            ("loading-explicit-id", loading, .view(.activateContentTabSwitcherCandidate(id("confirm-loading-A")))),
            ("empty-explicit-id", empty, .view(.activateContentTabSwitcherCandidate(id("confirm-empty-A")))),
            ("error-explicit-id", error, .view(.activateContentTabSwitcherCandidate(id("confirm-error-A")))),
            (
                "ineligible-window-explicit-id",
                ineligibleWindow,
                .view(.activateContentTabSwitcherCandidate(id("confirm-ineligible-A"))),
            ),
        ]

        for (name, state, action) in scenarios {
            let presentation = state.contentTabSwitcherPresentation
            let semanticSnapshot = ContentTabSemanticSnapshot(state)
            let previousActiveTabID = state.contentTabs.previousActiveTabID
            let store = TestStore(initialState: state) {
                FileManagerWindowCommandRoutingReducer()
            }

            await store.send(action)
            await store.finish()

            XCTAssertEqual(store.state.contentTabSwitcherPresentation, presentation, name)
            XCTAssertEqual(ContentTabSemanticSnapshot(store.state), semanticSnapshot, name)
            XCTAssertEqual(store.state.contentTabs.previousActiveTabID, previousActiveTabID, name)
        }
    }

    /// CTM-004-confirm_content_tab_switcher_selection: full FileManagerFeature composition은 stale focused window
    /// command를
    /// 거부하고 presentation을 보존한다.
    /// reconciliation exclusion 덕분에 stale focusedCandidateID가 live neighbor로 재매핑되지 않고 command handler가 직접
    /// 검증하는지 확인한다.
    /// - 검증 내용: FileManagerFeature composition, stale focused candidate, presentation와 semantic snapshot 보존
    /// - 사전 조건: live candidate projection과 일치하는 candidateIDs지만 stale focusedCandidateID인 automatic presentation
    /// - 기대 결과: window command 후 원본 presentation과 ContentTabSemanticSnapshot이 유지되고 effect가 없다.
    @MainActor
    func testStaleFocusedWindowCommandPreservesPresentationInProductionComposition() async {
        var state = makeSwitcherWindowState(prefix: "confirm-production-stale")
        let presentation = FileManagerContentTabSwitcherPresentation(
            source: .automatic,
            candidateIDs: ids("confirm-production-stale-B", "confirm-production-stale-A"),
            focusedCandidateID: id("confirm-production-stale-missing"),
        )
        state.contentTabSwitcherPresentation = presentation
        let semanticSnapshot = ContentTabSemanticSnapshot(state)
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }

        await store.send(.request(.activateContentTabSwitcherSelection))
        await store.finish()

        XCTAssertEqual(store.state.contentTabSwitcherPresentation, presentation)
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), semanticSnapshot)
    }

    /// CTM-004-confirm_content_tab_switcher_selection: interaction-ineligible window은 focused window command를 거부하고
    /// 원본 presentation을 보존한다.
    /// parent reconciliation이 ineligible activation 전후에 candidate snapshot을 바꾸지 않는 full production 경로를 검증한다.
    /// - 검증 내용: FileManagerFeature composition, interaction eligibility, presentation와 semantic snapshot 보존
    /// - 사전 조건: isClosing window와 live focused current candidate를 포함한 축약 candidate presentation
    /// - 기대 결과: window command 후 축약 presentation과 ContentTabSemanticSnapshot이 유지되고 effect가 없다.
    @MainActor
    func testInteractionIneligibleWindowCommandPreservesPresentationInProductionComposition() async {
        var state = makeSwitcherWindowState(prefix: "confirm-production-ineligible")
        state.isClosing = true
        let presentation = FileManagerContentTabSwitcherPresentation(
            source: .automatic,
            candidateIDs: [id("confirm-production-ineligible-B")],
            focusedCandidateID: id("confirm-production-ineligible-B"),
        )
        state.contentTabSwitcherPresentation = presentation
        let semanticSnapshot = ContentTabSemanticSnapshot(state)
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }

        await store.send(.request(.activateContentTabSwitcherSelection))
        await store.finish()

        XCTAssertEqual(store.state.contentTabSwitcherPresentation, presentation)
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), semanticSnapshot)
    }

    /// CTM-004-present_focused_candidate: FileManagerHost content fixture가 1·5·6·10 card focus layout을 결정적으로 노출한다.
    /// 실제 host state를 후보 수별로 축약해 adaptive row geometry와 reducer focus의 manual observable을 검증한다.
    /// - 검증 내용: host fixture source/state, 1·5·6·10 후보 수, 균형 행 수, 단일 focused ContentTabID
    /// - 사전 조건: deterministic UUID/date dependency와 `.contentTabSwitcherContent` FileManagerHost fixture
    /// - 기대 결과: 각 card 수가 projection/view state에 그대로 반영되고 하나의 focus identity가 metadata를 바꾸지 않는다.
    @MainActor
    func testFileManagerHostContentFixtureExposesFocusCardLayoutCases() async {
        let perceptionCheckingWasEnabled = PerceptionCore.isPerceptionCheckingEnabled
        PerceptionCore.isPerceptionCheckingEnabled = false
        defer { PerceptionCore.isPerceptionCheckingEnabled = perceptionCheckingWasEnabled }
        _ = NSApplication.shared

        let coordinator = withDependencies {
            $0.uuid = .constant(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 1)))
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        } operation: {
            FileManagerHostFixture.makeWindowController(preset: .contentTabSwitcherContent)
        }
        for cardCount in [1, 5, 6, 10] {
            var fixtureState = coordinator.store.contentTabs
            fixtureState.recentlyUsedTabIDs = Array(fixtureState.recentlyUsedTabIDs.prefix(cardCount))
            let presentation = FileManagerContentTabSwitcherPresentation(
                source: .automatic,
                contentTabs: fixtureState,
            )

            guard case let .content(rows) = ContentTabSwitcherViewState.make(
                source: presentation.source,
                contentTabs: fixtureState,
                focusedCandidateID: presentation.focusedCandidateID,
            ) else {
                return XCTFail("Expected content rows for card count \(cardCount)")
            }

            XCTAssertEqual(rows.count, cardCount)
            let expectedRowCounts = ContentTabSwitcherLayout.rowCounts(for: cardCount)
            XCTAssertEqual(
                ContentTabSwitcherLayout.rowCounts(for: rows.count),
                expectedRowCounts,
            )
            let balancedRows = ContentTabSwitcherLayout.balancedRows(from: rows)
            XCTAssertEqual(balancedRows.map(\.count), expectedRowCounts)
            XCTAssertEqual(balancedRows.flatMap(\.self).map(\.id), rows.map(\.id))
            let geometry = ContentTabSwitcherLayout.constrainedGeometry(
                candidateCount: cardCount,
                availableWidth: 960,
            )
            XCTAssertEqual(geometry.cardWidth, ContentTabSwitcherLayout.idealCardWidth)
            XCTAssertEqual(rows.filter(\.isFocused).count, 1)
            print(
                "FOCUS_FIXTURE_SUBCASE cards=\(cardCount) rows=\(ContentTabSwitcherLayout.rowCounts(for: rows.count)) "
                    + "focused=\(rows.first(where: { $0.isFocused })?.id.rawValue ?? "nil") PASS",
            )
        }
        await tearDownHostFixture(coordinator)
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: 전환기 표시와 해제가 Content Tab 의미 상태를 보존한다.
    /// window-local 표시 수명주기와 Escape·backdrop 공용 해제 action의 멱등성을 검증한다.
    /// - 검증 내용: 표시 source, 명시적 해제, 반복 표시/해제, Escape/backdrop 해제, 다른 window 불변성
    /// - 사전 조건: 선택과 MRU가 있는 독립된 두 개의 two-tab window
    /// - 기대 결과: 대상 window의 presentation만 변경되고 두 window의 Content Tab 의미 상태는 유지된다.
    @MainActor
    func testPresentationLifecyclePreservesContentTabState() async {
        let initialState = makeSwitcherWindowState(prefix: "focused")
        let unfocusedState = makeSwitcherWindowState(prefix: "unfocused")
        let initialSnapshot = ContentTabSemanticSnapshot(initialState)
        let unfocusedSnapshot = ContentTabSemanticSnapshot(unfocusedState)
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }

        await store.send(.request(.presentContentTabSwitcher(source: .automatic))) {
            $0.contentTabSwitcherPresentation = .init(source: .automatic, contentTabs: $0.contentTabs)
        }
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), initialSnapshot)
        XCTAssertEqual(ContentTabSemanticSnapshot(unfocusedState), unfocusedSnapshot)
        print("LIFECYCLE_SUBCASE present PASS")

        await store.send(.request(.presentContentTabSwitcher(source: .automatic)))
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), initialSnapshot)
        print("LIFECYCLE_SUBCASE repeated-present PASS")

        await store.send(.view(.dismissContentTabSwitcher)) {
            $0.contentTabSwitcherPresentation = nil
        }
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), initialSnapshot)
        print("LIFECYCLE_SUBCASE explicit-dismiss PASS")

        await store.send(.view(.dismissContentTabSwitcher))
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), initialSnapshot)
        print("LIFECYCLE_SUBCASE repeated-dismiss PASS")

        await store.send(.request(.presentContentTabSwitcher(source: .loading))) {
            $0.contentTabSwitcherPresentation = .init(source: .loading)
        }
        await store.send(.view(.dismissContentTabSwitcher)) {
            $0.contentTabSwitcherPresentation = nil
        }
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), initialSnapshot)
        print("LIFECYCLE_SUBCASE escape-equivalent-dismiss PASS")

        await store.send(.request(.presentContentTabSwitcher(source: .error(message: "Unable to load recent tabs.")))) {
            $0.contentTabSwitcherPresentation = .init(source: .error(message: "Unable to load recent tabs."))
        }
        await store.send(.view(.dismissContentTabSwitcher)) {
            $0.contentTabSwitcherPresentation = nil
        }
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), initialSnapshot)
        XCTAssertEqual(ContentTabSemanticSnapshot(unfocusedState), unfocusedSnapshot)
        print("LIFECYCLE_SUBCASE backdrop-equivalent-dismiss PASS")
        print("LIFECYCLE_SUBCASE focused-window-locality PASS")
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: 전환기 focus는 current와 독립적으로 후보를 wrap한다.
    /// next가 stable ContentTabID만 변경하고 Content Tab 의미 상태를 변경하지 않는지 검증한다.
    /// - 검증 내용: initial current focus, forward wrap, Current/focus 분리
    /// - 사전 조건: active B와 MRU `[B, A]`인 two-tab window
    /// - 기대 결과: focus만 B↔A로 이동하고 active/MRU/selection/page/pane snapshot은 완전히 동일하다.
    @MainActor
    func testFocusNavigationWrapsWithoutMutatingContentTabState() async {
        let initialState = makeSwitcherWindowState(prefix: "focus")
        let semanticSnapshot = ContentTabSemanticSnapshot(initialState)
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }

        await store.send(.request(.presentContentTabSwitcher(source: .automatic))) {
            $0.contentTabSwitcherPresentation = .init(
                source: .automatic,
                contentTabs: $0.contentTabs,
            )
        }
        XCTAssertEqual(
            store.state.contentTabSwitcherPresentation?.candidateIDs,
            ids("focus-B", "focus-A"),
        )
        XCTAssertEqual(store.state.contentTabSwitcherPresentation?.focusedCandidateID, id("focus-B"))
        guard case let .content(rows) = ContentTabSwitcherViewState.make(
            source: .automatic,
            contentTabs: store.state.contentTabs,
        ) else {
            return XCTFail("Expected content rows")
        }
        XCTAssertEqual(rows.first(where: { $0.isCurrent })?.id, id("focus-B"))

        await store.send(.request(.moveContentTabSwitcherFocus(direction: .next))) {
            $0.contentTabSwitcherPresentation = .init(
                source: .automatic,
                candidateIDs: ids("focus-B", "focus-A"),
                focusedCandidateID: id("focus-A"),
            )
        }
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), semanticSnapshot)

        await store.send(.request(.moveContentTabSwitcherFocus(direction: .next))) {
            $0.contentTabSwitcherPresentation = .init(
                source: .automatic,
                candidateIDs: ids("focus-B", "focus-A"),
                focusedCandidateID: id("focus-B"),
            )
        }
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), semanticSnapshot)
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: 이전 방향 focus도 후보 ID 기준으로 wrap한다.
    /// previous가 첫 후보에서 마지막 후보로 이동하고 Content Tab 의미 상태를 보존하는지 검증한다.
    /// - 검증 내용: reverse wrap과 Current/focus 분리
    /// - 사전 조건: active B와 MRU `[B, A]`인 two-tab window
    /// - 기대 결과: focus만 B↔A로 이동하고 active/MRU/selection/page/pane snapshot은 동일하다.
    @MainActor
    func testPreviousFocusNavigationWrapsWithoutMutatingContentTabState() async {
        let initialState = makeSwitcherWindowState(prefix: "reverse")
        let semanticSnapshot = ContentTabSemanticSnapshot(initialState)
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }

        await store.send(.request(.presentContentTabSwitcher(source: .automatic))) {
            $0.contentTabSwitcherPresentation = .init(source: .automatic, contentTabs: $0.contentTabs)
        }
        await store.send(.request(.moveContentTabSwitcherFocus(direction: .previous))) {
            $0.contentTabSwitcherPresentation = .init(
                source: .automatic,
                candidateIDs: ids("reverse-B", "reverse-A"),
                focusedCandidateID: id("reverse-A"),
            )
        }
        await store.send(.request(.moveContentTabSwitcherFocus(direction: .previous))) {
            $0.contentTabSwitcherPresentation = .init(
                source: .automatic,
                candidateIDs: ids("reverse-B", "reverse-A"),
                focusedCandidateID: id("reverse-B"),
            )
        }
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), semanticSnapshot)
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: 단일 후보와 status presentation은 focus를 이동하지 않는다.
    /// zero/one 후보와 loading/error presentation이 안정적인 no-op 경계를 지키는지 검증한다.
    /// - 검증 내용: single candidate, loading, error focus nil
    /// - 사전 조건: one live candidate 또는 status presentation
    /// - 기대 결과: presentation이 바뀌지 않고 focus가 nil로 유지된다.
    @MainActor
    func testFocusNavigationNoOpForSingleAndStatusPresentations() async throws {
        let emptyPresentation = FileManagerContentTabSwitcherPresentation(
            source: .automatic,
            contentTabs: makeState(tabs: [], active: nil, mru: ["stale"]),
        )
        XCTAssertEqual(emptyPresentation.candidateIDs, [])
        XCTAssertNil(emptyPresentation.focusedCandidateID)

        var singleWindowState = makeSwitcherWindowState(prefix: "single-window")
        singleWindowState.contentTabs = makeState(
            tabs: [tab("single")],
            active: "single",
            mru: ["single"],
        )
        let singleStore = TestStore(initialState: singleWindowState) {
            FileManagerFeature()
        }
        await singleStore.send(.request(.presentContentTabSwitcher(source: .automatic))) {
            $0.contentTabSwitcherPresentation = .init(
                source: .automatic,
                contentTabs: $0.contentTabs,
            )
        }
        let singlePresentation = try XCTUnwrap(singleStore.state.contentTabSwitcherPresentation)
        await singleStore.send(.request(.moveContentTabSwitcherFocus(direction: .next)))
        XCTAssertEqual(singleStore.state.contentTabSwitcherPresentation, singlePresentation)

        await singleStore.send(.request(.presentContentTabSwitcher(source: .error(message: "Failure")))) {
            $0.contentTabSwitcherPresentation = .init(source: .error(message: "Failure"))
        }
        XCTAssertNil(singleStore.state.contentTabSwitcherPresentation?.focusedCandidateID)

        let loadingWindowState = makeSwitcherWindowState(prefix: "loading")
        let loadingStore = TestStore(initialState: loadingWindowState) {
            FileManagerFeature()
        }
        await loadingStore.send(.request(.presentContentTabSwitcher(source: .loading))) {
            $0.contentTabSwitcherPresentation = .init(source: .loading)
        }
        let loadingPresentation = try XCTUnwrap(loadingStore.state.contentTabSwitcherPresentation)
        await loadingStore.send(.request(.moveContentTabSwitcherFocus(direction: .next)))
        XCTAssertEqual(loadingStore.state.contentTabSwitcherPresentation, loadingPresentation)
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: live 후보 갱신은 삭제된 focus를 이전 위치로 복구한다.
    /// child close가 presentation snapshot과 focus를 함께 최신 projection으로 수렴시키는지 검증한다.
    /// - 검증 내용: 중간 삭제 successor, 끝 삭제 last candidate, empty projection, semantic snapshot 불변
    /// - 사전 조건: `[A, B, C]` candidate snapshot에서 B 또는 C를 닫는 두 개의 독립 window
    /// - 기대 결과: B 삭제는 C, C 삭제는 B, 마지막 후보 삭제는 nil focus와 empty surface이다.
    @MainActor
    func testLiveCandidateRefreshRepairsRemovedFocusByPriorPosition() async {
        var middleState = makeSwitcherWindowState(prefix: "repair-middle")
        let middleC = id("repair-middle-C")
        middleState.contentTabs.activeTabID = id("repair-middle-A")
        middleState.contentTabs.tabs.append(tab(middleC.rawValue))
        middleState.contentTabs.recentlyUsedTabIDs = ids("repair-middle-A", "repair-middle-B", "repair-middle-C")
        middleState.contentTabSwitcherPresentation = .init(
            source: .automatic,
            candidateIDs: ids("repair-middle-A", "repair-middle-B", "repair-middle-C"),
            focusedCandidateID: id("repair-middle-B"),
        )
        let middleStore = TestStore(initialState: middleState) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        middleStore.exhaustivity = .off // child close lifecycle action은 focus reconciliation 범위 밖이다.

        await middleStore.send(.contentTabs(.commitClose(id("repair-middle-B"))))
        await middleStore.finish()

        XCTAssertEqual(
            middleStore.state.contentTabSwitcherPresentation,
            .init(
                source: .automatic,
                candidateIDs: ids("repair-middle-A", "repair-middle-C"),
                focusedCandidateID: middleC,
            ),
        )
        XCTAssertEqual(middleStore.state.contentTabs.activeTabID, id("repair-middle-A"))
        XCTAssertEqual(
            middleStore.state.contentTabs.recentlyUsedTabIDs,
            ids("repair-middle-A", "repair-middle-B", "repair-middle-C"),
        )
        let middleSemanticBeforeReconciliation = ContentTabSemanticSnapshot(middleStore.state)
        await middleStore.send(.request(.presentContentTabSwitcher(source: .automatic)))
        XCTAssertEqual(
            ContentTabSemanticSnapshot(middleStore.state),
            middleSemanticBeforeReconciliation,
        )

        var endState = makeSwitcherWindowState(prefix: "repair-end")
        let endC = id("repair-end-C")
        endState.contentTabs.tabs.append(tab(endC.rawValue))
        endState.contentTabs.recentlyUsedTabIDs = ids("repair-end-A", "repair-end-B", "repair-end-C")
        endState.contentTabSwitcherPresentation = .init(
            source: .automatic,
            candidateIDs: ids("repair-end-A", "repair-end-B", "repair-end-C"),
            focusedCandidateID: endC,
        )
        let endStore = TestStore(initialState: endState) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        endStore.exhaustivity = .off // child close lifecycle action은 focus reconciliation 범위 밖이다.

        await endStore.send(.contentTabs(.commitClose(endC)))
        await endStore.finish()

        XCTAssertEqual(
            endStore.state.contentTabSwitcherPresentation,
            .init(
                source: .automatic,
                candidateIDs: ids("repair-end-A", "repair-end-B"),
                focusedCandidateID: id("repair-end-B"),
            ),
        )
        let endSemanticBeforeReconciliation = ContentTabSemanticSnapshot(endStore.state)
        await endStore.send(.request(.presentContentTabSwitcher(source: .automatic)))
        XCTAssertEqual(ContentTabSemanticSnapshot(endStore.state), endSemanticBeforeReconciliation)

        var emptyWindowState = FileManagerWindowState()
        emptyWindowState.contentTabs = makeState(tabs: [], active: nil, mru: ["stale"])
        emptyWindowState.contentTabSwitcherPresentation = .init(
            source: .automatic,
            candidateIDs: ids("repair-empty-A"),
            focusedCandidateID: id("repair-empty-A"),
        )
        let emptyStore = TestStore(initialState: emptyWindowState) {
            FileManagerFeature()
        }
        await emptyStore.send(.contentTabs(.toggleSelection(id("repair-empty-A")))) {
            $0.contentTabSwitcherPresentation = .init(source: .automatic)
        }
        XCTAssertEqual(emptyStore.state.contentTabSwitcherPresentation, .init(source: .automatic))
        XCTAssertEqual(
            ContentTabSwitcherViewState.make(source: .automatic, contentTabs: emptyStore.state.contentTabs),
            .empty(.init(message: "No recent tabs", accessibilityLabel: "No recent tabs")),
        )
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: live identity와 metadata/MRU 변화가 focus를 점프시키지 않는다.
    /// 최신 projection 순서가 바뀌어도 살아 있는 focused ID와 전체 semantic snapshot을 보존하는지 검증한다.
    /// - 검증 내용: metadata update, MRU reorder, focus identity retention
    /// - 사전 조건: focus C인 `[A, B, C]` snapshot과 active A
    /// - 기대 결과: metadata/MRU 변경 후에도 focus C가 유지되고 reconciliation이 semantic state를 추가 변경하지 않는다.
    @MainActor
    func testLiveCandidateRefreshRetainsIdentityAcrossMetadataAndMRUReorder() async {
        var state = makeSwitcherWindowState(prefix: "retain")
        let tabC = id("retain-C")
        state.contentTabs.tabs.append(tab(tabC.rawValue))
        state.contentTabs.recentlyUsedTabIDs = ids("retain-A", "retain-B", "retain-C")
        state.contentTabSwitcherPresentation = .init(
            source: .automatic,
            candidateIDs: ids("retain-A", "retain-B", "retain-C"),
            focusedCandidateID: tabC,
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off // anchor 변경의 부수 effect는 focus reconciliation 범위 밖이다.

        await store.send(.contentTabs(.updateRuntimePageAnchor(
            id("retain-B"),
            .directory(path: "/retain/updated"),
        )))
        await store.finish()

        XCTAssertEqual(store.state.contentTabSwitcherPresentation?.focusedCandidateID, tabC)
        XCTAssertEqual(
            store.state.contentTabSwitcherPresentation?.candidateIDs,
            ids("retain-A", "retain-B", "retain-C"),
        )
        XCTAssertEqual(store.state.contentTabs.activeTabID, id("retain-B"))
        XCTAssertEqual(store.state.contentTabs.recentlyUsedTabIDs, ids("retain-A", "retain-B", "retain-C"))
        XCTAssertEqual(store.state.contentTabSwitcherPresentation?.candidateIDs.contains(tabC), true)
        let semanticBeforeReconciliation = ContentTabSemanticSnapshot(store.state)
        await store.send(.request(.presentContentTabSwitcher(source: .automatic)))
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), semanticBeforeReconciliation)
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: stale focus navigation은 old snapshot 방향의 live
    /// neighbor를 고른다.
    /// 제거된 B가 남은 `[A, C]` 사이에서 next는 C, previous는 A를 선택하는지 검증한다.
    /// - 검증 내용: stale focus next/previous, wrong-neighbor adversarial distinction, atomic snapshot update
    /// - 사전 조건: old `[A, B, C]`, stale focus B, live `[A, C]`
    /// - 기대 결과: next/previous가 각각 방향에 맞는 neighbor를 선택하고 focus는 live IDs 안에 있다.
    @MainActor
    func testStaleFocusNavigationUsesDirectionCorrectLiveNeighbor() async {
        for (direction, expectedFocus) in [
            (ContentTabSwitcherFocusDirection.next, id("stale-C")),
            (.previous, id("stale-D")),
        ] {
            var state = makeSwitcherWindowState(prefix: "stale")
            state.contentTabs.tabs.append(contentsOf: [tab("stale-D"), tab("stale-C")])
            state.contentTabs.recentlyUsedTabIDs = ids("stale-A", "stale-D", "stale-C")
            state.contentTabSwitcherPresentation = .init(
                source: .automatic,
                candidateIDs: ids("stale-A", "stale-D", "stale-B", "stale-C"),
                focusedCandidateID: id("stale-B"),
            )
            let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
                $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            }
            store.exhaustivity = .off // focus command는 semantic effect를 내지 않는다.

            await store.send(.request(.moveContentTabSwitcherFocus(direction: direction)))

            XCTAssertEqual(
                store.state.contentTabSwitcherPresentation?.candidateIDs,
                ids("stale-A", "stale-D", "stale-C"),
            )
            XCTAssertEqual(store.state.contentTabSwitcherPresentation?.focusedCandidateID, expectedFocus)
            XCTAssertEqual(store.state.contentTabSwitcherPresentation?.candidateIDs.contains(expectedFocus), true)
        }
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: rapid close/reorder/navigation은 focus를 항상 live 범위로
    /// 유지한다.
    /// 연속 child mutation과 양방향 navigation 사이에서 presentation snapshot과 focus의 원자적 수렴을 검증한다.
    /// - 검증 내용: close, reorder, next, previous, close-to-empty sequence
    /// - 사전 조건: 네 개의 live candidate와 첫 후보 focus
    /// - 기대 결과: 각 transition 뒤 focus가 nil 또는 최신 candidateIDs 내부이며 sequence가 deterministic이다.
    @MainActor
    func testRapidCandidateRefreshSequenceRemainsDeterministicAndInBounds() async {
        var state = makeSwitcherWindowState(prefix: "rapid")
        state.contentTabs.tabs.append(contentsOf: [tab("rapid-C"), tab("rapid-D")])
        state.contentTabs.recentlyUsedTabIDs = ids("rapid-A", "rapid-B", "rapid-C", "rapid-D")
        state.contentTabSwitcherPresentation = .init(
            source: .automatic,
            candidateIDs: ids("rapid-A", "rapid-B", "rapid-C", "rapid-D"),
            focusedCandidateID: id("rapid-B"),
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off // sequence의 close lifecycle effect는 focus 범위 밖이다.

        await store.send(.contentTabs(.close(id("rapid-B"))))
        await store.send(.contentTabs(.reorder(
            sourceID: id("rapid-D"),
            targetID: id("rapid-A"),
            placement: .before,
        )))
        await store.send(.request(.moveContentTabSwitcherFocus(direction: .next)))
        await store.send(.request(.moveContentTabSwitcherFocus(direction: .previous)))
        await store.finish()

        let presentation = store.state.contentTabSwitcherPresentation
        XCTAssertEqual(presentation?.candidateIDs, ids("rapid-C", "rapid-A", "rapid-D"))
        XCTAssertEqual(presentation.map { $0.candidateIDs.contains($0.focusedCandidateID ?? id("missing")) }, true)
        let semanticBeforeReconciliation = ContentTabSemanticSnapshot(store.state)
        await store.send(.request(.presentContentTabSwitcher(source: .automatic)))
        XCTAssertEqual(ContentTabSemanticSnapshot(store.state), semanticBeforeReconciliation)
    }

    /// CTM-004-switch_content_tab_via_used_content_tabs_switcher: 모든 recent-tab transaction busy 상태에서 표시를 차단한다.
    /// VOY-464 admission 경계를 공유해 topology transaction 중 presentation도 끼어들지 않는지 검증한다.
    /// - 검증 내용: 열한 busy guard 각각의 whole-window no-op과 action/effect/feedback 부재
    /// - 사전 조건: two-tab window에 각 busy sentinel을 하나씩 독립 적용
    /// - 기대 결과: 모든 subcase에서 presentation을 포함한 전체 window state가 동일하다.
    @MainActor
    func testPresentationIsBlockedByEveryRecentTabTransaction() async {
        let tabID = ContentTabID(rawValue: "busy-B")
        let requestID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 66))
        let ownerID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 67))
        let subcases = busyCloseAndPinSubcases(tabID: tabID, requestID: requestID, ownerID: ownerID)
            + busyTopologySubcases(tabID: tabID, requestID: requestID, ownerID: ownerID)

        for (name, applyBusyState) in subcases {
            var state = makeSwitcherWindowState(prefix: "busy")
            applyBusyState(&state)
            let alerts = LockIsolated(0)
            let store = TestStore(initialState: state) {
                FileManagerFeature()
            } withDependencies: {
                $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in
                    alerts.withValue { $0 += 1 }
                }
            }

            await store.send(.request(.presentContentTabSwitcher(source: .automatic)))

            XCTAssertEqual(store.state, state, name)
            XCTAssertEqual(alerts.value, 0, name)
            print("BUSY_SUBCASE \(name) PASS")
        }
    }
}
