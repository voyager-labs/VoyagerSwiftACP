import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
final class CTM001SelectContentTabsTests: XCTestCase {
    private static var retainedAppKitWindows: [NSWindow] = []

    // MARK: - CTM-001-select_content_tabs

    /// CTM-001-select_content_tabs: Content Tab primary 입력 modifier 전체 조합 분류 검증
    /// modifier-only 선택 계약에서 Shift 우선순위와 Command/Option toggle을 확인함
    /// - 검증 내용: Command, Shift, Option의 8개 truth table과 classifier 결과
    /// - 사전 조건: Control/right-click은 UI에서 우선 소비되며 classifier 호출 대상이 아님
    /// - 기대 결과: Shift 포함은 range, 그 외 Command 또는 Option 포함은 toggle, plain은 activate를 반환함
    func testContentTabSelectionInputClassifier_coversCompleteModifierTruthTable() {
        let truthTable: [(KeyModifiers, ContentTabRowPrimaryIntent)] = [
            ([], .activate),
            (.option, .toggleSelection),
            (.command, .toggleSelection),
            ([.command, .option], .toggleSelection),
            (.shift, .selectRange),
            ([.shift, .option], .selectRange),
            ([.command, .shift], .selectRange),
            ([.command, .shift, .option], .selectRange),
        ]

        for (modifiers, expected) in truthTable {
            XCTAssertEqual(
                ContentTabSelectionInputClassifier.classify(modifiers),
                expected,
                "modifier rawValue \(modifiers.rawValue) 분류가 일치해야 함",
            )
        }
    }

    /// CTM-001-select_content_tabs: actual NSButton primary pointer route의 상호배제 검증
    /// 실제 window event queue를 통과한 click이 modifier 우선순위에 맞는 callback 하나만 호출하는지 확인함
    /// - 검증 내용: Command/Shift/Option 8개 조합의 callback route와 총 호출 수
    /// - 사전 조건: 실제 NSWindow에 설치된 ContentTabSidebarButton과 valid windowNumber의 down/up event
    /// - 기대 결과: plain은 activate, Command/Option은 toggle, Shift 조합은 range를 정확히 한 번 호출함
    func testContentTabButton_primaryPointerRoutesAreMutuallyExclusive() throws {
        let cases: [(NSEvent.ModifierFlags, ContentTabButtonRoute)] = [
            ([], .activate),
            (.command, .toggleSelection),
            (.option, .toggleSelection),
            ([.command, .option], .toggleSelection),
            (.shift, .selectRange),
            ([.command, .shift], .selectRange),
            ([.option, .shift], .selectRange),
            ([.command, .option, .shift], .selectRange),
        ]

        for (modifiers, expectedRoute) in cases {
            try withContentTabButtonFixture { fixture in
                try dispatchPrimaryClick(on: fixture.button, modifiers: modifiers)

                XCTAssertLessThanOrEqual(fixture.recorder.routes.count, 1)
                XCTAssertEqual(fixture.recorder.routes, [expectedRoute])
            }
        }
    }

    /// CTM-001-select_content_tabs: Control-primary와 right-click context menu 소유권 검증
    /// context 입력이 activation/selection callback 없이 기존 per-tab menu만 해석하는지 확인함
    /// - 검증 내용: Control-primary callback 합계, right event의 menu title, menu 구성의 side-effect 부재
    /// - 사전 조건: 실제 NSWindow button과 Control left click 및 valid rightMouseDown event
    /// - 기대 결과: callback은 0회이고 unpinned menu는 Duplicate/Pin/Close를 그대로 제공함
    func testContentTabButton_contextInputsExposeMenuWithoutPrimaryAction() throws {
        try withContentTabButtonFixture { fixture in
            try dispatchPrimaryClick(on: fixture.button, modifiers: .control)
            let rightMouseDown = try mouseEvent(
                .rightMouseDown,
                on: fixture.button,
                modifiers: [],
                locationInButton: insideButtonLocation,
                eventNumber: 1,
            )
            let menu = try XCTUnwrap(fixture.button.menu(for: rightMouseDown))

            XCTAssertTrue(fixture.recorder.routes.isEmpty)
            XCTAssertLessThanOrEqual(fixture.recorder.routes.count, 1)
            XCTAssertEqual(menu.items.map(\.title), ["Duplicate", "Pin", "Close"])
            XCTAssertTrue(fixture.recorder.menuActions.isEmpty)
        }
    }

    /// CTM-001-select_content_tabs: reorderable button의 sub-threshold drag-out 취소 검증
    /// 4pt 미만 이동 뒤 bounds 밖 mouse-up은 click과 reorder drag 어느 쪽도 확정하지 않음을 확인함
    /// - 검증 내용: queued mouseDragged/mouseUp 이후 primary callback과 drag-session start 총합
    /// - 사전 조건: 실제 window button 우측 경계 안쪽 down에서 2pt 이동한 바깥 mouse-up event
    /// - 기대 결과: activate/toggle/range와 drag-session start가 모두 0회임
    func testContentTabButton_subthresholdDragOutsideCancelsPrimaryAction() throws {
        try withContentTabButtonFixture { fixture in
            try dispatchSubthresholdDragOutside(on: fixture.button, modifiers: .command)

            XCTAssertTrue(fixture.recorder.routes.isEmpty)
            XCTAssertTrue(fixture.recorder.draggingItems.isEmpty)
        }
    }

    /// CTM-001-select_content_tabs: reorder threshold를 넘으면 drag만 정확히 한 번 시작함
    /// 임계값을 넘긴 최신 drag event로 source가 selection callback 없이 native writer를 시작하는지 확인함
    /// - 검증 내용: above-threshold drag의 session start 수, drag event identity, writer token, primary callback 총합
    /// - 사전 조건: 실제 NSWindow의 unpinned button과 4pt 임계값을 넘는 leftMouseDragged event
    /// - 기대 결과: drag-session은 1회, selection callback은 0회이고 dismantle은 writer-owned token만 제거함
    func testContentTabButton_thresholdDragStartsOnceWithoutPrimaryAction() throws {
        try withContentTabButtonFixture { fixture in
            try dispatchThresholdDrag(on: fixture.button, modifiers: .shift)

            XCTAssertTrue(fixture.recorder.routes.isEmpty)
            XCTAssertEqual(fixture.recorder.draggingItems.count, 1)
            XCTAssertEqual(fixture.recorder.dragStartEvents.map(\.type), [.leftMouseDragged])
            XCTAssertEqual(fixture.recorder.dragStartEvents.map(\.eventNumber), [2])
            let draggingItem = try XCTUnwrap(fixture.recorder.draggingItems.first?.first)
            let writer = try XCTUnwrap(draggingItem.item as? FileManagerTopNavigationReorderPasteboardWriter)
            XCTAssertEqual(fixture.sessionStore.entry?.token, writer.token)

            fixture.button.dismantle()
            XCTAssertNil(fixture.sessionStore.entry)
        }
    }

    /// CTM-001-select_content_tabs: pinned button은 reorder drag source를 시작하지 않음
    /// non-reorderable row가 기존 NSButton tracking만 사용하고 drag seam에는 도달하지 않는지 확인함
    /// - 검증 내용: threshold 초과 pointer sequence의 drag-session start와 primary callback 총합
    /// - 사전 조건: drag-source configuration이 nil인 실제 pinned ContentTabSidebarButton
    /// - 기대 결과: drag-session과 primary callback이 모두 0회임
    func testContentTabButton_pinnedRowNeverStartsReorderDrag() throws {
        try withContentTabButtonFixture(isPinned: true) { fixture in
            try dispatchPrimaryDragOutside(on: fixture.button, modifiers: [])

            XCTAssertTrue(fixture.recorder.draggingItems.isEmpty)
            XCTAssertTrue(fixture.recorder.routes.isEmpty)
            XCTAssertNil(fixture.sessionStore.entry)
        }
    }

    /// CTM-001-select_content_tabs: programmatic press의 plain activation 검증
    /// keyboard와 accessibility press가 stale pointer modifier 없이 plain target/action을 사용하는지 확인함
    /// - 검증 내용: NSButton.performClick의 callback route와 총 호출 수
    /// - 사전 조건: 실제 NSWindow에 설치됐지만 pointer tracking 중이 아닌 ContentTabSidebarButton
    /// - 기대 결과: activate callback만 정확히 한 번 호출되고 selection callback은 호출되지 않음
    func testContentTabButton_performClickUsesPlainActivation() {
        withContentTabButtonFixture { fixture in
            fixture.button.performClick(nil)

            XCTAssertLessThanOrEqual(fixture.recorder.routes.count, 1)
            XCTAssertEqual(fixture.recorder.routes, [.activate])
        }
    }

    /// CTM-001-select_content_tabs: representable update 이후 최신 callback과 control 상태 검증
    /// SwiftUI identity/action 갱신이 old closure를 보존하지 않고 presentation/accessibility/enabled 값을 함께 교체하는지 확인함
    /// - 검증 내용: update 후 Option click receiver, accessibility 값, enabled 상태, horizontal sizing priority
    /// - 사전 조건: old callback으로 설치된 실제 window button을 new callback과 새 root로 update함
    /// - 기대 결과: old callback은 0회, new toggle은 1회이며 최신 control metadata와 sizing policy가 반영됨
    func testContentTabButton_updateUsesNewestCallbacksAndControlState() throws {
        let oldRecorder = ContentTabButtonRecorder()
        let newRecorder = ContentTabButtonRecorder()
        let updatedSessionStore = FileManagerTopNavigationReorderLocalSessionStore()
        let updatedSourceID = ContentTabID(rawValue: "updated-source")

        try withContentTabButtonFixture(recorder: oldRecorder) { fixture in
            configure(
                fixture.button,
                recorder: newRecorder,
                sessionStore: updatedSessionStore,
                sourceID: updatedSourceID,
                rootView: AnyView(Text("Updated")),
                accessibilityValue: "Inactive, Selected",
                isEnabled: true,
            )
            fixture.button.dragSessionStartOverride = { items, event in
                newRecorder.draggingItems.append(items)
                newRecorder.dragStartEvents.append(event)
                _ = fixture.window.nextEvent(
                    matching: .leftMouseUp,
                    until: .distantPast,
                    inMode: .eventTracking,
                    dequeue: true,
                )
            }
            try dispatchPrimaryClick(on: fixture.button, modifiers: .option)
            try dispatchThresholdDrag(on: fixture.button, modifiers: [])

            XCTAssertTrue(oldRecorder.routes.isEmpty)
            XCTAssertNil(fixture.sessionStore.entry)
            XCTAssertEqual(newRecorder.routes, [.toggleSelection])
            XCTAssertEqual(newRecorder.draggingItems.count, 1)
            XCTAssertEqual(updatedSessionStore.entry?.payload.sourceID, .contentTab(updatedSourceID))
            XCTAssertEqual(fixture.button.accessibilityValue() as? String, "Inactive, Selected")
            XCTAssertTrue(fixture.button.isEnabled)
            XCTAssertEqual(fixture.button.contentHuggingPriority(for: .horizontal), .defaultLow)
            XCTAssertEqual(fixture.button.contentCompressionResistancePriority(for: .horizontal), .defaultLow)
        }
    }

    /// CTM-001-select_content_tabs: hosted presentation의 pointer 투명성과 NSButton hit owner 검증
    /// full padded/background presentation이 보이되 pointer와 accessibility owner는 concrete NSButton 하나인지 확인함
    /// - 검증 내용: button center hitTest identity, hosted child hitTest, accessibility label/value
    /// - 사전 조건: 실제 NSWindow에서 full row frame을 가진 ContentTabSidebarButton
    /// - 기대 결과: center hit은 button으로 해석되고 hosted child는 hit target이 아니며 button이 four-state 값을 노출함
    func testContentTabButton_hitTestResolvesToSingleButtonOwner() throws {
        try withContentTabButtonFixture { fixture in
            let buttonHitLocation = NSPoint(x: fixture.button.frame.midX, y: fixture.button.frame.midY)
            let presentationHitLocation = NSPoint(x: fixture.button.bounds.midX, y: fixture.button.bounds.midY)
            let presentationView = try XCTUnwrap(fixture.button.subviews.first)

            XCTAssertTrue(fixture.button.hitTest(buttonHitLocation) === fixture.button)
            XCTAssertNil(presentationView.hitTest(presentationHitLocation))
            XCTAssertEqual(fixture.button.accessibilityLabel(), "Content Tab")
            XCTAssertEqual(fixture.button.accessibilityValue() as? String, "Active, Not Selected")
        }
    }

    /// CTM-001-select_content_tabs: native NSMenu command callback 보존 검증
    /// menu 생성은 side effect가 없고 각 기존 command가 대응 callback 하나만 dispatch하는지 확인함
    /// - 검증 내용: unpinned Duplicate/Pin/Close와 pinned Duplicate/Unpin target/action route
    /// - 사전 조건: 실제 button의 current menu를 NSApplication target/action으로 실행함
    /// - 기대 결과: menu 구성 시 callback 0회, 각 item 실행 시 동일 이름의 기존 callback이 순서대로 1회씩 호출됨
    func testContentTabButton_contextMenuCommandsPreserveExistingActions() throws {
        try withContentTabButtonFixture { fixture in
            let unpinnedMenu = try XCTUnwrap(fixture.button.menu)
            XCTAssertTrue(fixture.recorder.menuActions.isEmpty)

            for item in unpinnedMenu.items {
                let action = try XCTUnwrap(item.action)
                XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item))
            }
            XCTAssertEqual(fixture.recorder.menuActions, [.duplicate, .pin, .close])

            fixture.recorder.menuActions.removeAll()
            configure(
                fixture.button,
                recorder: fixture.recorder,
                sessionStore: fixture.sessionStore,
                isPinned: true,
            )
            let pinnedMenu = try XCTUnwrap(fixture.button.menu)
            XCTAssertEqual(pinnedMenu.items.map(\.title), ["Duplicate", "Unpin"])
            XCTAssertTrue(fixture.recorder.menuActions.isEmpty)

            for item in pinnedMenu.items {
                let action = try XCTUnwrap(item.action)
                XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item))
            }
            XCTAssertEqual(fixture.recorder.menuActions, [.duplicate, .unpin])
        }
    }

    /// CTM-001-select_content_tabs: 기본 선택 상태와 selector 및 생성 경로의 zero selection 검증
    /// active identity와 selected identity가 독립적인 runtime 상태인지 확인함
    /// - 검증 내용: 빈 직접 초기화와 active를 만드는 factory가 selected count 0을 제공함
    /// - 사전 조건: 기본 상태와 Home/bootstrap/pinned restore 생성 경로
    /// - 기대 결과: active 유무와 관계없이 explicit selection 전에는 selected set이 비고 bulk가 비활성화됨
    func testSelectionDefaultsAndSelectors_reflectRuntimeSelection() throws {
        var state = ContentTabState()
        let factoryStates = [
            ContentTabState.withHomeTab(),
            ContentTabState.bootstrapping(),
            ContentTabState.restoringPinnedRecords(from: ContentTabPinnedRecordStore()).state,
        ]

        XCTAssertEqual(state.selectedTabIDs, [])
        XCTAssertNil(state.selectionAnchorID)
        XCTAssertEqual(state.selectedTabCount, 0)
        XCTAssertFalse(state.isBulkActionEnabled)
        for factoryState in factoryStates {
            XCTAssertNotNil(try XCTUnwrap(factoryState.activeTabID))
            XCTAssertEqual(factoryState.selectedTabIDs, [])
            XCTAssertNil(factoryState.selectionAnchorID)
            XCTAssertEqual(factoryState.selectedTabCount, 0)
            XCTAssertFalse(factoryState.isBulkActionEnabled)
        }

        let firstID = ContentTabID(rawValue: "selector-first")
        let secondID = ContentTabID(rawValue: "selector-second")
        state = ContentTabState(
            tabs: [tab(id: firstID, isPinned: false), tab(id: secondID, isPinned: false)],
            activeTabID: firstID,
        )
        state.selectedTabIDs = [firstID, secondID]

        XCTAssertEqual(state.selectedTabCount, 2)
        XCTAssertTrue(state.isBulkActionEnabled)
    }

    /// CTM-001-select_content_tabs: Sidebar selection presentation의 membership 검증
    /// canonical selected IDs를 별도 observable state 없이 순수 값으로 전달하는지 확인함
    /// - 검증 내용: 렌더링 여부와 무관한 선택 ID membership
    /// - 사전 조건: A와 Sidebar에 없는 missing ID가 선택된 presentation
    /// - 기대 결과: A와 missing만 selected이며 원본 selected ID 집합이 보존됨
    func testContentTabSelectionPresentation_preservesMembership() {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let missingTab = ContentTabID(rawValue: "missing")
        let presentation = ContentTabSelectionPresentation(selectedTabIDs: [tabA, missingTab])

        XCTAssertTrue(presentation.isSelected(tabA))
        XCTAssertFalse(presentation.isSelected(tabB))
        XCTAssertTrue(presentation.isSelected(missingTab))
        XCTAssertEqual(presentation.selectedTabIDs, [tabA, missingTab])
    }

    /// CTM-001-select_content_tabs: active와 selected의 canonical identity 독립성 검증
    /// state construction이 valid active를 explicit selection으로 승격하지 않는지 확인함
    /// - 검증 내용: active tab identity와 zero selected membership
    /// - 사전 조건: active A와 inactive B를 가진 ContentTabState
    /// - 기대 결과: A는 active지만 selected set은 비어 있음
    func testContentTabStateConstruction_keepsValidActiveTabUnselected() {
        let tabID = ContentTabID(rawValue: "truth-table")
        let inactiveID = ContentTabID(rawValue: "inactive")
        let state = ContentTabState(
            tabs: [tab(id: tabID, isPinned: false), tab(id: inactiveID, isPinned: false)],
            activeTabID: tabID,
        )

        XCTAssertEqual(state.selectedTabIDs, [])
        XCTAssertEqual(state.selectedTabCount, 0)
        XCTAssertFalse(state.isBulkActionEnabled)
    }

    /// CTM-001-select_content_tabs: Sidebar selection View action의 Delegate relay 검증
    /// Sidebar leaf reducer가 toggle/range 요청을 상태 변경 없이 정확히 한 번 relay하는지 확인함
    /// - 검증 내용: toggle/range View→Delegate 순서와 payload
    /// - 사전 조건: 기본 Sidebar 상태와 고정 A/B Content Tab ID
    /// - 기대 결과: Sidebar 상태는 불변이며 각 요청이 대응 Delegate로 한 번씩 전송됨
    func testSidebarSelectionRouting_relaysToggleAndRangeWithoutLocalState() async {
        let tabA = ContentTabID(rawValue: "leaf-A")
        let tabB = ContentTabID(rawValue: "leaf-B")
        let store = TestStore(initialState: FileManagerSidebarState()) {
            FileManagerSidebarFeature()
        }

        await store.send(.view(.toggleContentTabSelection(tabA)))
        await store.receive { action in
            guard case let .delegate(.toggleContentTabSelection(id)) = action else { return false }
            return id == tabA
        }
        await store.send(.view(.selectContentTabRange(to: tabB)))
        await store.receive { action in
            guard case let .delegate(.selectContentTabRange(to: id)) = action else { return false }
            return id == tabB
        }
        // store.finish() 불필요: 모든 effect가 receive로 소비됨
    }

    /// CTM-001-select_content_tabs: Sidebar empty-space selection collapse ownership 검증
    /// genuine scroll background action이 Sidebar leaf를 거쳐 canonical ContentTab owner로 전달되는지 확인함
    /// - 검증 내용: View → Delegate → Window → ContentTab action chain
    /// - 사전 조건: active A와 selected A/B, anchor B인 FileManager Window state
    /// - 기대 결과: 최종 selection과 anchor가 active A 하나로 축소됨
    func testSidebarEmptySpaceClick_routesToCanonicalActiveSelectionCollapse() async {
        let tabA = ContentTabID(rawValue: "empty-space-a")
        let tabB = ContentTabID(rawValue: "empty-space-b")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [tab(id: tabA, isPinned: false), tab(id: tabB, isPinned: false)],
            activeTabID: tabA,
        )
        state.contentTabs.selectedTabIDs = [tabA, tabB]
        state.contentTabs.selectionAnchorID = tabB
        let store = TestStore(initialState: state) { FileManagerFeature() }

        await store.send(.sidebar(.view(.collapseContentTabSelectionToActive)))
        await store.receive(\.sidebar.delegate.collapseContentTabSelectionToActive)
        await store.receive(\.contentTabs.collapseSelectionToActive) {
            $0.contentTabs.selectedTabIDs = [tabA]
            $0.contentTabs.selectionAnchorID = tabA
        }
    }

    /// CTM-001-select_content_tabs: Sidebar 빈 viewport가 행과 분리된 hit target을 사용함
    /// eager VStack의 잔여 Spacer만 빈 공간 pointer surface를 소유하는지 확인함
    /// - 검증 내용: viewport minHeight, LazyVStack 형제 Spacer, canonical collapse action wiring
    /// - 사전 조건: production SidebarView source
    /// - 기대 결과: background gesture 없이 전용 Spacer만 collapse action을 전송함
    func testSidebarEmptyViewportUsesDedicatedSiblingHitTarget() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot
            .appendingPathComponent("Sources/VoyagerPagesFileManager/Sidebar/Ui/SidebarView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let geometryStart = try XCTUnwrap(source.range(of: "GeometryReader { proxy in"))
        let geometryEnd = try XCTUnwrap(source.range(
            of: ".clipped()",
            range: geometryStart.upperBound ..< source.endIndex,
        ))
        let geometrySource = source[geometryStart.lowerBound ..< geometryEnd.upperBound]
        let hitTargetStart = try XCTUnwrap(geometrySource.range(of: "Spacer(minLength: 0)"))
        let hitTargetEnd = try XCTUnwrap(geometrySource.range(
            of: "                    }\n                    .frame(",
            range: hitTargetStart.upperBound ..< geometrySource.endIndex,
        ))
        let hitTargetSource = geometrySource[hitTargetStart.lowerBound ..< hitTargetEnd.lowerBound]

        XCTAssertTrue(geometrySource.contains("minHeight: proxy.size.height"))
        XCTAssertTrue(geometrySource.contains("VStack(spacing: 0)"))
        XCTAssertTrue(geometrySource.contains("LazyVStack(alignment: .leading, spacing: 0)"))
        XCTAssertTrue(hitTargetSource.contains(".frame(maxWidth: .infinity)"))
        XCTAssertTrue(hitTargetSource.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(hitTargetSource.contains(".onTapGesture"))
        XCTAssertTrue(hitTargetSource.contains("collapseContentTabSelectionToActive"))
        XCTAssertFalse(geometrySource.contains(".background {"))
    }

    /// CTM-001-select_content_tabs: Window Sidebar selection Delegate routing 검증
    /// Window boundary가 toggle/range만 기존 ContentTab action으로 변환하는지 확인함
    /// - 검증 내용: toggle/range Delegate→ContentTab action 순서와 payload
    /// - 사전 조건: 기본 Window 상태와 고정 A/B Content Tab ID
    /// - 기대 결과: Window 상태는 불변이며 각 Delegate가 대응 canonical action을 한 번씩 전송함
    func testWindowSelectionDelegates_routeToggleAndRangeToExistingActions() async {
        let tabA = ContentTabID(rawValue: "router-A")
        let tabB = ContentTabID(rawValue: "router-B")
        let state = FileManagerFeature.State()
        let selectionOrder = state.contentTabSelectionOrderedIDs
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        }

        await store.send(.sidebar(.delegate(.toggleContentTabSelection(tabA))))
        await store.receive { action in
            guard case let .contentTabs(.toggleSelection(id)) = action else { return false }
            return id == tabA
        }
        await store.send(.sidebar(.delegate(.selectContentTabRange(to: tabB))))
        await store.receive { action in
            guard case let .contentTabs(.selectRange(to: id, orderedIDs: orderedIDs)) = action else {
                return false
            }
            return id == tabB && orderedIDs == selectionOrder
        }

        XCTAssertEqual(store.state, state)
        // store.finish() 불필요: 모든 effect가 receive로 소비됨
    }

    /// CTM-001-select_content_tabs: pinned range는 raw tab 저장 순서가 아니라 Sidebar 표시 순서를 사용한다.
    /// - 검증 내용: C/A/B 표시에서 C→A range가 중간 raw tab B를 포함하지 않음
    /// - 사전 조건: raw tabs A/B/C, pinned top-navigation C/A/B, anchor C
    /// - 기대 결과: selection은 C/A만 포함하고 B는 제외됨
    func testWindowRangeSelectionUsesPinnedTopNavigationDisplayOrder() async {
        let tabA = ContentTabID(rawValue: "display-range-A")
        let tabB = ContentTabID(rawValue: "display-range-B")
        let tabC = ContentTabID(rawValue: "display-range-C")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                tab(id: tabA, isPinned: true),
                tab(id: tabB, isPinned: true),
                tab(id: tabC, isPinned: true),
            ],
            activeTabID: tabC,
        )
        state.contentTabs.selectedTabIDs = [tabC]
        state.contentTabs.selectionAnchorID = tabC
        state.optimisticTopNavigationOrder = .init(items: [
            .contentTab(tabC),
            .contentTab(tabA),
            .contentTab(tabB),
        ])
        state.syncContentTabSidebarItems()
        let store = TestStore(initialState: state) { FileManagerFeature() }

        await store.send(.sidebar(.delegate(.selectContentTabRange(to: tabA))))
        await store.receive { action in
            guard case let .contentTabs(.selectRange(to: id, orderedIDs: orderedIDs)) = action else {
                return false
            }
            return id == tabA && orderedIDs == [tabC, tabA, tabB]
        } assert: {
            $0.contentTabs.selectedTabIDs = [tabC, tabA]
        }

        XCTAssertFalse(store.state.contentTabs.selectedTabIDs.contains(tabB))
    }

    /// CTM-001-select_content_tabs: 다른 Content Tab plain click의 exclusive selection 검증
    /// Sidebar plain activation이 새 active 하나로 explicit selection을 축소하는지 확인함
    /// - 검증 내용: setCurrent 이후 collapse 순서와 selected IDs/anchor 및 active identity
    /// - 사전 조건: A active, A/B selected, anchor B인 두 Content Tab Window 상태
    /// - 기대 결과: active가 B로 전환되고 selection/anchor도 B 하나로 축소됨
    func testPlainClickDifferentTab_activatesAndCollapsesSelectionToTarget() async {
        let tabA = ContentTabID(rawValue: "plain-different-A")
        let tabB = ContentTabID(rawValue: "plain-different-B")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [tab(id: tabA, isPinned: false), tab(id: tabB, isPinned: false)],
            activeTabID: tabA,
        )
        state.contentTabs.selectedTabIDs = [tabA, tabB]
        state.contentTabs.selectionAnchorID = tabB
        state.tabContentStates = [tabA: state.content, tabB: state.content]
        let store = TestStore(initialState: state) {
            Reduce<FileManagerFeature.State, FileManagerFeature.Action> { state, action in
                if case let .contentTabs(contentTabAction) = action {
                    return ContentTabFeature()
                        .reduce(into: &state.contentTabs, action: contentTabAction)
                        .map { .contentTabs($0) }
                }
                return FileManagerWindowRoutingReducer().reduce(into: &state, action: action)
            }
        }
        await store.send(.sidebar(.delegate(.selectContentTab(tabB))))
        await store.receive { action in
            guard case let .contentTabs(.setCurrent(id)) = action else { return false }
            return id == tabB
        } assert: {
            $0.contentTabs.activeTabID = tabB
            $0.contentTabs.previousActiveTabID = tabA
            $0.contentTabs.selectedTabIDs = [tabA, tabB]
        }
        await store.receive(\.contentTabs.collapseSelectionToActive) {
            $0.contentTabs.selectedTabIDs = [tabB]
            $0.contentTabs.selectionAnchorID = tabB
        }
        XCTAssertEqual(store.state.contentTabs.activeTabID, tabB)
    }

    /// CTM-001-select_content_tabs: 현재 active Content Tab plain click의 exclusive selection 검증
    /// 이미 active인 row의 재활성화도 해당 active 하나로 explicit selection을 축소하는지 확인함
    /// - 검증 내용: setCurrent no-op 이후 collapse 순서와 selected IDs/anchor 및 active identity
    /// - 사전 조건: A active, A/B selected, anchor B인 두 Content Tab Window 상태
    /// - 기대 결과: active identity는 유지되고 selection/anchor는 A 하나로 축소됨
    func testPlainClickActiveTab_collapsesSelectionToActive() async {
        let tabA = ContentTabID(rawValue: "plain-active-A")
        let tabB = ContentTabID(rawValue: "plain-active-B")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [tab(id: tabA, isPinned: false), tab(id: tabB, isPinned: false)],
            activeTabID: tabA,
        )
        state.contentTabs.selectedTabIDs = [tabA, tabB]
        state.contentTabs.selectionAnchorID = tabB
        state.tabContentStates = [tabA: state.content, tabB: state.content]
        let store = TestStore(initialState: state) {
            Reduce<FileManagerFeature.State, FileManagerFeature.Action> { state, action in
                if case let .contentTabs(contentTabAction) = action {
                    return ContentTabFeature()
                        .reduce(into: &state.contentTabs, action: contentTabAction)
                        .map { .contentTabs($0) }
                }
                return FileManagerWindowRoutingReducer().reduce(into: &state, action: action)
            }
        }
        await store.send(.sidebar(.delegate(.selectContentTab(tabA))))
        await store.receive { action in
            guard case let .contentTabs(.setCurrent(id)) = action else { return false }
            return id == tabA
        }
        await store.receive(\.contentTabs.collapseSelectionToActive) {
            $0.contentTabs.selectedTabIDs = [tabA]
            $0.contentTabs.selectionAnchorID = tabA
        }
        XCTAssertEqual(store.state.contentTabs.activeTabID, tabA)
    }

    /// CTM-001-select_content_tabs: 사라진 Content Tab plain click의 selection 보존 검증
    /// stale Sidebar row가 현재 active 기준 collapse를 유발하지 않는지 확인함
    /// - 검증 내용: routed ContentTab action 부재와 active/selected IDs/anchor 불변
    /// - 사전 조건: A active, A/B selected이며 요청 target은 tabs에 없는 Window 상태
    /// - 기대 결과: stale activation 요청은 무시되고 canonical ContentTab state가 유지됨
    func testPlainClickMissingTab_doesNotCollapseCurrentSelection() async {
        let tabA = ContentTabID(rawValue: "plain-missing-A")
        let tabB = ContentTabID(rawValue: "plain-missing-B")
        let missingTab = ContentTabID(rawValue: "plain-missing-target")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [tab(id: tabA, isPinned: false), tab(id: tabB, isPinned: false)],
            activeTabID: tabA,
        )
        state.contentTabs.selectedTabIDs = [tabA, tabB]
        state.contentTabs.selectionAnchorID = tabB
        let originalContentTabs = state.contentTabs
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        }

        await store.send(.sidebar(.delegate(.selectContentTab(missingTab))))

        XCTAssertEqual(store.state.contentTabs, originalContentTabs)
    }

    /// CTM-001-select_content_tabs: Sidebar New Tab 성공 시 selection 독립성 전체 chain 검증
    /// Window route와 canonical ContentTab reducer가 기존 selection을 보존하며 새 Home tab을 활성화하는지 확인함
    /// - 검증 내용: open(.homeDefault) 단일 route, selected IDs/anchor, 새 active Home tab
    /// - 사전 조건: 기존 active tab이 선택되어 있고 selection anchor가 존재하며 max-tab limit 미만인 Window 상태
    /// - 기대 결과: 새 Home tab은 active가 되지만 기존 selection/anchor는 그대로 유지됨
    func testOpenContentTab_opensWithoutChangingSelection() async throws {
        let existingTabID = ContentTabID(rawValue: "new-tab-existing")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [tab(id: existingTabID, isPinned: false)],
            activeTabID: existingTabID,
        )
        state.contentTabs.selectedTabIDs = [existingTabID]
        state.contentTabs.selectionAnchorID = existingTabID
        let store = TestStore(initialState: state) {
            Reduce<FileManagerFeature.State, FileManagerFeature.Action> { state, action in
                if case let .contentTabs(contentTabAction) = action {
                    return ContentTabFeature()
                        .reduce(into: &state.contentTabs, action: contentTabAction)
                        .map { .contentTabs($0) }
                }
                return FileManagerWindowRoutingReducer().reduce(into: &state, action: action)
            }
        }
        // store.exhaustivity = .off: open이 생성하는 무작위 ContentTabID는 최종 canonical state로 검증한다.
        store.exhaustivity = .off

        await store.send(.sidebar(.delegate(.openContentTab)))
        await store.receive { action in
            guard case .contentTabs(.open(.homeDefault)) = action else { return false }
            return true
        }
        let openedTab = try XCTUnwrap(store.state.contentTabs.tabs.last)
        XCTAssertEqual(store.state.contentTabs.tabs.count, 2)
        XCTAssertEqual(openedTab.anchor, .homeDefault)
        XCTAssertEqual(openedTab.page, .home)
        XCTAssertEqual(store.state.contentTabs.activeTabID, openedTab.id)
        XCTAssertEqual(store.state.contentTabs.previousActiveTabID, existingTabID)
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [existingTabID])
        XCTAssertEqual(store.state.contentTabs.selectionAnchorID, existingTabID)
    }

    /// CTM-001-select_content_tabs: Sidebar New Tab max-tab 제한 시 selection context 보존 검증
    /// Window route가 cleanup 전에 max-tab guard를 적용해 active transition 없는 요청을 완전한 no-op으로 유지하는지 확인함
    /// - 검증 내용: routed ContentTab action 부재, tab count와 selected IDs/anchor/active identity 불변
    /// - 사전 조건: maxTabs 개수의 tab, 첫 tab active, 첫/마지막 tab selected, 마지막 tab anchor인 Window 상태
    /// - 기대 결과: 새 tab과 cleanup action이 없고 전체 canonical ContentTab state가 그대로 유지됨
    func testOpenContentTab_atMaxTabsPreservesSelectionAnchorAndActiveIdentity() async {
        let tabIDs = (0 ..< ContentTabConstants.maxTabs).map {
            ContentTabID(rawValue: "new-tab-max-\($0)")
        }
        let activeTabID = tabIDs[0]
        let anchorTabID = tabIDs[tabIDs.count - 1]
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: .init(uniqueElements: tabIDs.map { tab(id: $0, isPinned: false) }),
            activeTabID: activeTabID,
        )
        state.contentTabs.selectedTabIDs = [activeTabID, anchorTabID]
        state.contentTabs.selectionAnchorID = anchorTabID
        let originalContentTabs = state.contentTabs
        let store = TestStore(initialState: state) {
            Reduce<FileManagerFeature.State, FileManagerFeature.Action> { state, action in
                if case let .contentTabs(contentTabAction) = action {
                    return ContentTabFeature()
                        .reduce(into: &state.contentTabs, action: contentTabAction)
                        .map { .contentTabs($0) }
                }
                return FileManagerWindowRoutingReducer().reduce(into: &state, action: action)
            }
        }

        await store.send(.sidebar(.delegate(.openContentTab)))

        XCTAssertEqual(store.state.contentTabs, originalContentTabs)
        XCTAssertEqual(store.state.contentTabs.tabs.count, ContentTabConstants.maxTabs)
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [activeTabID, anchorTabID])
        XCTAssertEqual(store.state.contentTabs.selectionAnchorID, anchorTabID)
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeTabID)
    }

    /// CTM-001-select_content_tabs: Sidebar toggle/range 전체 reducer chain 및 projection 격리 검증
    /// View부터 canonical ContentTab reducer까지 이어지면서 active와 broad projection이 유지되는지 확인함
    /// - 검증 내용: View→Delegate→ContentTab 순서, selected IDs/anchor, Sidebar/Home/pending sentinel
    /// - 사전 조건: A active, pinned B previous이며 projection sentinel이 source와 의도적으로 어긋난 Window 상태
    /// - 기대 결과: toggle B와 range A가 selection만 변경하고 active 및 broad projection sentinel은 보존함
    func testSidebarSelectionToggleAndRange_fullChainPreservesBroadProjectionSentinels() async {
        let tabA = ContentTabID(rawValue: "chain-A")
        let tabB = ContentTabID(rawValue: "chain-B")
        let stalePendingTab = ContentTabID(rawValue: "chain-stale")
        let state = makeWindowSelectionSentinelState(
            tabA: tabA,
            tabB: tabB,
            stalePendingTab: stalePendingTab,
        )
        let pendingSentinel = state.pendingDirectoryReloadTabIDs
        let sidebarProjectionSentinel = state.sidebar.contentTabSidebarItems
        let homeLocationSentinel = state.content.homeLocationItems
        let homeFavoriteSentinel = state.content.homeFavoriteItems
        let selectionOrder = state.contentTabSelectionOrderedIDs
        let store = TestStore(initialState: state) { FileManagerFeature() }

        await store.send(.sidebar(.view(.toggleContentTabSelection(tabB))))
        await store.receive { action in
            guard case let .sidebar(.delegate(.toggleContentTabSelection(id))) = action else { return false }
            return id == tabB
        }
        await store.receive { action in
            guard case let .contentTabs(.toggleSelection(id)) = action else { return false }
            return id == tabB
        } assert: {
            $0.contentTabs.selectedTabIDs = [tabB]
            $0.contentTabs.selectionAnchorID = tabB
        }
        await store.send(.sidebar(.view(.selectContentTabRange(to: tabA))))
        await store.receive { action in
            guard case let .sidebar(.delegate(.selectContentTabRange(to: id))) = action else { return false }
            return id == tabA
        }
        await store.receive { action in
            guard case let .contentTabs(.selectRange(to: id, orderedIDs: orderedIDs)) = action else {
                return false
            }
            return id == tabA && orderedIDs == selectionOrder
        } assert: {
            $0.contentTabs.selectedTabIDs = [tabA, tabB]
        }

        XCTAssertEqual(store.state.contentTabs.activeTabID, tabA)
        XCTAssertEqual(store.state.contentTabs.previousActiveTabID, tabB)
        XCTAssertEqual(store.state.contentTabs.selectionAnchorID, tabB)
        XCTAssertEqual(store.state.pendingDirectoryReloadTabIDs, pendingSentinel)
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems, sidebarProjectionSentinel)
        XCTAssertEqual(store.state.content.homeLocationItems, homeLocationSentinel)
        XCTAssertEqual(store.state.content.homeFavoriteItems, homeFavoriteSentinel)
        // store.finish() 불필요: 모든 effect가 receive로 소비됨
    }

    /// CTM-001-select_content_tabs: interleaved raw tabs의 selection 전용 pinned-first ordering 검증
    /// - 검증 내용: pinned 상대 순서 뒤 unpinned 상대 순서를 반환하면서 raw tabs를 변경하지 않음
    /// - 사전 조건: raw 순서가 U1, P1, U2, P2, U3인 다섯 탭
    /// - 기대 결과: selection 순서는 P1, P2, U1, U2, U3이고 tabs는 입력 순서와 동일함
    func testSelectionOrdering_interleavedTabsReturnsPinnedFirstWithoutMutatingRawTabs() {
        let unpinned1 = ContentTabID(rawValue: "U1")
        let pinned1 = ContentTabID(rawValue: "P1")
        let unpinned2 = ContentTabID(rawValue: "U2")
        let pinned2 = ContentTabID(rawValue: "P2")
        let unpinned3 = ContentTabID(rawValue: "U3")
        let rawTabs: IdentifiedArrayOf<ContentTabItem> = [
            tab(id: unpinned1, isPinned: false),
            tab(id: pinned1, isPinned: true),
            tab(id: unpinned2, isPinned: false),
            tab(id: pinned2, isPinned: true),
            tab(id: unpinned3, isPinned: false),
        ]
        let state = ContentTabState(tabs: rawTabs, activeTabID: unpinned1)

        XCTAssertEqual(state.selectionOrderedTabIDs, [pinned1, pinned2, unpinned1, unpinned2, unpinned3])
        XCTAssertEqual(state.tabs, rawTabs)
        XCTAssertEqual(Array(state.tabs.ids), [unpinned1, pinned1, unpinned2, pinned2, unpinned3])
    }

    /// CTM-001-select_content_tabs: stale selected ID와 stale anchor reconciliation 및 상태 격리 검증
    /// - 검증 내용: 현재 identity와 selected IDs를 교집합하고 stale anchor만 제거하며 비선택 상태를 보존함
    /// - 사전 조건: A/B는 현재 탭, X는 stale이며 selected가 A/X이고 anchor가 X인 metadata 포함 상태
    /// - 기대 결과: A 선택은 생존하고 X 선택/anchor만 제거되며 active/previous/tabs/pinned/recent/runtime metadata는 동일함
    func testReconcileSelection_removesStaleSelectionAndAnchorWithoutChangingOtherState() {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let staleTab = ContentTabID(rawValue: "X")
        let pinnedAt = Date(timeIntervalSince1970: 451)
        let recentlyClosed = ClosedContentTabSnapshot(
            page: .directory,
            anchor: .directory(path: "/closed"),
            wasPinned: false,
            closedAt: pinnedAt,
            title: "Closed",
            iconName: "folder",
        )
        let pinnedRecord = ContentTabPinnedRecord(
            id: tabB.rawValue,
            page: .directory,
            anchor: .directory(path: "/B"),
            title: "B",
            iconName: "folder",
            pinnedAt: pinnedAt,
        )
        var state = ContentTabState(
            tabs: [tab(id: tabA, isPinned: false), tab(id: tabB, isPinned: true)],
            activeTabID: tabB,
            previousActiveTabID: tabA,
            recentlyClosed: recentlyClosed,
            pinnedRecords: [tabB: pinnedRecord],
            pendingPinnedRecordIDs: [tabB],
            pinnedRecordPersistenceError: "sentinel",
        )
        state.selectedTabIDs = [tabA, staleTab]
        state.selectionAnchorID = staleTab
        let tabsBefore = state.tabs
        let activeBefore = state.activeTabID
        let previousBefore = state.previousActiveTabID
        let recentlyClosedBefore = state.recentlyClosed
        let pinnedRecordsBefore = state.pinnedRecords
        let pendingPinnedRecordIDsBefore = state.pendingPinnedRecordIDs
        let persistenceErrorBefore = state.pinnedRecordPersistenceError

        state.reconcileSelection()

        XCTAssertEqual(state.selectedTabIDs, [tabA])
        XCTAssertNil(state.selectionAnchorID)
        XCTAssertEqual(state.tabs, tabsBefore)
        XCTAssertEqual(state.activeTabID, activeBefore)
        XCTAssertEqual(state.previousActiveTabID, previousBefore)
        XCTAssertEqual(state.recentlyClosed, recentlyClosedBefore)
        XCTAssertEqual(state.pinnedRecords, pinnedRecordsBefore)
        XCTAssertEqual(state.pendingPinnedRecordIDs, pendingPinnedRecordIDsBefore)
        XCTAssertEqual(state.pinnedRecordPersistenceError, persistenceErrorBefore)
    }

    /// CTM-001-select_content_tabs: 선택 집합에 없는 유효 anchor의 reconciliation 보존 검증
    /// - 검증 내용: anchor identity가 현재 tabs에 존재하면 selected membership과 무관하게 유지함
    /// - 사전 조건: 현재 A/B 탭, selected는 A 하나이고 anchor는 선택되지 않은 B
    /// - 기대 결과: reconcile 후 selected A와 valid-unselected anchor B가 모두 유지됨
    func testReconcileSelection_preservesValidUnselectedAnchor() {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        var state = ContentTabState(
            tabs: [tab(id: tabA, isPinned: false), tab(id: tabB, isPinned: false)],
            activeTabID: tabA,
        )
        state.selectedTabIDs = [tabA]
        state.selectionAnchorID = tabB

        state.reconcileSelection()

        XCTAssertEqual(state.selectedTabIDs, [tabA])
        XCTAssertEqual(state.selectionAnchorID, tabB)
    }

    /// CTM-001-select_content_tabs: selected active tab 제거 후 fallback selection 독립성 검증
    /// 제거된 selected/anchor identity만 정리하고 active fallback을 암묵적으로 선택하지 않는지 확인함
    /// - 검증 내용: commitClose의 selected/anchor reconciliation과 active fallback
    /// - 사전 조건: A가 active/selected/anchor이고 B는 선택되지 않은 두 Content Tab 상태
    /// - 기대 결과: A 제거 후 B가 active지만 selected set은 비고 anchor는 nil임
    func testCloseSelectedActiveTab_cleansRemovedIdentityWithoutSelectingFallback() {
        let tabA = ContentTabID(rawValue: "close-A")
        let tabB = ContentTabID(rawValue: "close-B")
        var state = ContentTabState(
            tabs: [tab(id: tabA, isPinned: false), tab(id: tabB, isPinned: false)],
            activeTabID: tabA,
        )
        state.selectedTabIDs = [tabA]
        state.selectionAnchorID = tabA

        _ = ContentTabFeature().reduce(into: &state, action: .commitClose(tabA))

        XCTAssertEqual(state.tabs.ids, [tabB])
        XCTAssertEqual(state.activeTabID, tabB)
        XCTAssertEqual(state.selectedTabIDs, [])
        XCTAssertNil(state.selectionAnchorID)
    }

    /// CTM-001-select_content_tabs: toggle과 active deselection 방지 정책 검증
    /// - 검증 내용: inactive membership 반전과 active command-toggle no-op membership
    /// - 사전 조건: A/B 탭과 B active baseline, A는 최초 미선택 상태
    /// - 기대 결과: A는 add/remove되고 B toggle은 active selection을 제거하지 않음
    func testToggleSelection_togglesInactiveButCannotDeselectActive() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let store = TestStore(initialState: ContentTabState(
            tabs: [tab(id: tabA, isPinned: false), tab(id: tabB, isPinned: true)],
            activeTabID: tabB,
            previousActiveTabID: tabA,
        )) {
            ContentTabFeature()
        }

        await store.send(.toggleSelection(tabA)) {
            $0.selectedTabIDs = [tabA]
            $0.selectionAnchorID = tabA
        }
        await store.send(.toggleSelection(tabA)) {
            $0.selectedTabIDs = []
        }
        await store.send(.toggleSelection(tabB)) {
            $0.selectedTabIDs = [tabB]
            $0.selectionAnchorID = tabB
        }

        XCTAssertEqual(store.state.selectedTabIDs, [tabB])
        XCTAssertEqual(store.state.selectionAnchorID, tabB)
        XCTAssertEqual(store.state.activeTabID, tabB)
        XCTAssertEqual(store.state.previousActiveTabID, tabA)
    }

    /// CTM-001-select_content_tabs: active baseline collapse와 idempotency 검증
    /// - 검증 내용: selected set/anchor를 active 하나로 축소한 뒤 같은 action의 whole-state no-op 확인
    /// - 사전 조건: A/B가 선택되고 anchor B이며 active/previous identity가 설정된 상태
    /// - 기대 결과: 첫 collapse 뒤 active A만 선택/anchor이고 두 번째 collapse 전후 전체 상태가 동일함
    func testCollapseSelectionToActive_keepsActiveBaselineAndIsIdempotent() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        var state = ContentTabState(
            tabs: [tab(id: tabA, isPinned: false), tab(id: tabB, isPinned: true)],
            activeTabID: tabA,
            previousActiveTabID: tabB,
        )
        state.selectedTabIDs = [tabA, tabB]
        state.selectionAnchorID = tabB
        let store = TestStore(initialState: state) { ContentTabFeature() }

        await store.send(.collapseSelectionToActive) {
            $0.selectedTabIDs = [tabA]
            $0.selectionAnchorID = tabA
        }
        let collapsedState = store.state
        await store.send(.collapseSelectionToActive)

        XCTAssertEqual(store.state, collapsedState)
    }

    /// CTM-001-select_content_tabs: forward/reverse/cross-divider range의 inclusive replace 검증
    /// - 검증 내용: pinned-first 순서에서 양방향 interval이 prior disjoint selection을 union하지 않고 교체함
    /// - 사전 조건: raw U1/P1/U2/P2/U3, anchor P1과 disjoint U3 selection
    /// - 기대 결과: U2 forward는 P1/P2/U1/U2, U3 anchor의 P2 reverse는 P2/U1/U2/U3만 선택함
    func testSelectRange_forwardReverseAndCrossDividerReplacePriorSelection() async {
        let unpinned1 = ContentTabID(rawValue: "U1")
        let pinned1 = ContentTabID(rawValue: "P1")
        let unpinned2 = ContentTabID(rawValue: "U2")
        let pinned2 = ContentTabID(rawValue: "P2")
        let unpinned3 = ContentTabID(rawValue: "U3")
        var state = ContentTabState(
            tabs: [
                tab(id: unpinned1, isPinned: false),
                tab(id: pinned1, isPinned: true),
                tab(id: unpinned2, isPinned: false),
                tab(id: pinned2, isPinned: true),
                tab(id: unpinned3, isPinned: false),
            ],
            activeTabID: unpinned1,
        )
        state.selectedTabIDs = [unpinned3]
        state.selectionAnchorID = pinned1
        let store = TestStore(initialState: state) { ContentTabFeature() }

        await store.send(.selectRange(to: unpinned2, orderedIDs: store.state.selectionOrderedTabIDs)) {
            $0.selectedTabIDs = [pinned1, pinned2, unpinned1, unpinned2]
        }
        await store.send(.toggleSelection(unpinned3)) {
            $0.selectedTabIDs.insert(unpinned3)
            $0.selectionAnchorID = unpinned3
        }
        await store.send(.selectRange(to: pinned2, orderedIDs: store.state.selectionOrderedTabIDs)) {
            $0.selectedTabIDs = [pinned2, unpinned1, unpinned2, unpinned3]
        }

        XCTAssertEqual(store.state.selectionAnchorID, unpinned3)
        XCTAssertFalse(store.state.selectedTabIDs.contains(pinned1))
    }

    /// CTM-001-select_content_tabs: nil/stale anchor의 target-only fallback 검증
    /// - 검증 내용: anchor를 ordering에서 찾을 수 없으면 기존 selection을 target 하나로 교체하고 anchor를 갱신함
    /// - 사전 조건: A/B 현재 탭과 stale X, nil anchor state 및 stale anchor state
    /// - 기대 결과: 두 state 모두 B 하나만 선택하고 anchor B로 수렴함
    func testSelectRange_nilOrStaleAnchorFallsBackToTargetOnlySelection() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let staleTab = ContentTabID(rawValue: "X")
        let tabs: IdentifiedArrayOf<ContentTabItem> = [
            tab(id: tabA, isPinned: false),
            tab(id: tabB, isPinned: true),
        ]
        var nilAnchorState = ContentTabState(tabs: tabs, activeTabID: tabA)
        nilAnchorState.selectedTabIDs = [tabA]
        let nilAnchorStore = TestStore(initialState: nilAnchorState) { ContentTabFeature() }

        await nilAnchorStore.send(.selectRange(to: tabB, orderedIDs: nilAnchorStore.state.selectionOrderedTabIDs)) {
            $0.selectedTabIDs = [tabB]
            $0.selectionAnchorID = tabB
        }

        var staleAnchorState = ContentTabState(tabs: tabs, activeTabID: tabA)
        staleAnchorState.selectedTabIDs = [tabA]
        staleAnchorState.selectionAnchorID = staleTab
        let staleAnchorStore = TestStore(initialState: staleAnchorState) { ContentTabFeature() }

        await staleAnchorStore.send(.selectRange(
            to: tabB,
            orderedIDs: staleAnchorStore.state.selectionOrderedTabIDs,
        )) {
            $0.selectedTabIDs = [tabB]
            $0.selectionAnchorID = tabB
        }
    }

    /// CTM-001-select_content_tabs: valid-unselected anchor 기반 range 검증
    /// - 검증 내용: toggle deselection으로 selected set에서 빠진 유효 anchor도 range 시작점으로 사용함
    /// - 사전 조건: U1/U2/U3 중 U1 selected이며 toggle로 deselect 예정
    /// - 기대 결과: anchor U1은 유지되고 U3 range가 U1/U2/U3 interval을 선택함
    func testSelectRange_usesValidAnchorEvenWhenAnchorIsNotSelected() async {
        let tab1 = ContentTabID(rawValue: "U1")
        let tab2 = ContentTabID(rawValue: "U2")
        let tab3 = ContentTabID(rawValue: "U3")
        var state = ContentTabState(
            tabs: [
                tab(id: tab1, isPinned: false),
                tab(id: tab2, isPinned: false),
                tab(id: tab3, isPinned: false),
            ],
            activeTabID: tab2,
        )
        state.selectedTabIDs = [tab1]
        let store = TestStore(initialState: state) { ContentTabFeature() }

        await store.send(.toggleSelection(tab1)) {
            $0.selectedTabIDs = []
            $0.selectionAnchorID = tab1
        }
        await store.send(.selectRange(to: tab3, orderedIDs: store.state.selectionOrderedTabIDs)) {
            $0.selectedTabIDs = [tab1, tab2, tab3]
        }

        XCTAssertEqual(store.state.selectionAnchorID, tab1)
    }

    /// CTM-001-select_content_tabs: reorder 직후 range가 갱신된 pinned-first 표시 순서를 사용함
    /// - 검증 내용: reorder가 selection/anchor를 보존하고 이어진 range가 새 unpinned 상대 순서의 interval을 선택함
    /// - 사전 조건: raw U1/P1/U2/P2/U3, anchor U3에서 U3를 U1 앞으로 reorder
    /// - 기대 결과: 새 표시 순서 P1/P2/U3/U1/U2 기준 U3...U2인 U3/U1/U2만 선택됨
    func testReorderThenSelectRange_usesUpdatedPinnedFirstDisplayedOrder() async {
        let unpinned1 = ContentTabID(rawValue: "U1")
        let pinned1 = ContentTabID(rawValue: "P1")
        let unpinned2 = ContentTabID(rawValue: "U2")
        let pinned2 = ContentTabID(rawValue: "P2")
        let unpinned3 = ContentTabID(rawValue: "U3")
        var state = ContentTabState(
            tabs: [
                tab(id: unpinned1, isPinned: false),
                tab(id: pinned1, isPinned: true),
                tab(id: unpinned2, isPinned: false),
                tab(id: pinned2, isPinned: true),
                tab(id: unpinned3, isPinned: false),
            ],
            activeTabID: unpinned2,
            previousActiveTabID: unpinned1,
        )
        state.selectedTabIDs = [unpinned2, unpinned3]
        state.selectionAnchorID = unpinned3
        let store = TestStore(initialState: state) { ContentTabFeature() }

        await store.send(.reorder(sourceID: unpinned3, targetID: unpinned1, placement: .before)) {
            $0.tabs = [
                self.tab(id: unpinned3, isPinned: false),
                self.tab(id: pinned1, isPinned: true),
                self.tab(id: unpinned1, isPinned: false),
                self.tab(id: pinned2, isPinned: true),
                self.tab(id: unpinned2, isPinned: false),
            ]
        }
        XCTAssertEqual(store.state.selectionOrderedTabIDs, [pinned1, pinned2, unpinned3, unpinned1, unpinned2])
        XCTAssertEqual(store.state.selectedTabIDs, Set([unpinned2, unpinned3]))
        XCTAssertEqual(store.state.selectionAnchorID, unpinned3)

        await store.send(.selectRange(to: unpinned2, orderedIDs: store.state.selectionOrderedTabIDs)) {
            $0.selectedTabIDs = [unpinned3, unpinned1, unpinned2]
        }

        XCTAssertEqual(store.state.activeTabID, unpinned2)
        XCTAssertEqual(store.state.previousActiveTabID, unpinned1)
        XCTAssertEqual(store.state.selectionAnchorID, unpinned3)
    }

    /// CTM-001-select_content_tabs: invalid toggle/range의 whole ContentTabState no-op 검증
    /// - 검증 내용: 존재하지 않는 target을 identity validation에서 거부하고 reconciliation도 실행하지 않음
    /// - 사전 조건: A/B 현재 탭, stale X가 selected와 anchor에 남은 상태, invalid Z target
    /// - 기대 결과: invalid toggle과 range 각각 전후 전체 상태가 byte-semantic equality를 유지함
    func testInvalidToggleAndRange_leaveWholeContentTabStateUnchanged() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let staleTab = ContentTabID(rawValue: "X")
        let invalidTab = ContentTabID(rawValue: "Z")
        var state = ContentTabState(
            tabs: [tab(id: tabA, isPinned: false), tab(id: tabB, isPinned: true)],
            activeTabID: tabB,
            previousActiveTabID: tabA,
        )
        state.selectedTabIDs = [tabA, staleTab]
        state.selectionAnchorID = staleTab
        let store = TestStore(initialState: state) { ContentTabFeature() }

        await store.send(.toggleSelection(invalidTab))
        XCTAssertEqual(store.state, state)
        await store.send(.selectRange(to: invalidTab, orderedIDs: store.state.selectionOrderedTabIDs))
        XCTAssertEqual(store.state, state)
    }

    /// CTM-001-select_content_tabs: Window post-reduce selection action 격리 검증
    /// - 검증 내용: valid selection은 child selection만 변경하고 pending/Sidebar/Home projection sentinel을 보존함
    /// - 사전 조건: 서로 어긋난 source/cached projection과 stale pending ID를 가진 FileManagerFeature state
    /// - 기대 결과: valid toggle은 selection만 변경하고 invalid toggle/range는 whole Window state no-op임
    func testWindowSelectionActions_preserveProjectionSentinelsAndInvalidActionsAreWholeStateNoOps() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let invalidTab = ContentTabID(rawValue: "invalid")
        let stalePendingTab = ContentTabID(rawValue: "stale-pending")
        let state = makeWindowSelectionSentinelState(
            tabA: tabA,
            tabB: tabB,
            stalePendingTab: stalePendingTab,
        )
        let pendingSentinel = state.pendingDirectoryReloadTabIDs
        let sidebarProjectionSentinel = state.sidebar.contentTabSidebarItems
        let homeLocationSentinel = state.content.homeLocationItems
        let homeFavoriteSentinel = state.content.homeFavoriteItems
        let store = TestStore(initialState: state) { FileManagerFeature() }

        await store.send(.contentTabs(.toggleSelection(tabB))) {
            $0.contentTabs.selectedTabIDs = [tabB]
            $0.contentTabs.selectionAnchorID = tabB
        }

        XCTAssertEqual(store.state.pendingDirectoryReloadTabIDs, pendingSentinel)
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems, sidebarProjectionSentinel)
        XCTAssertEqual(store.state.content.homeLocationItems, homeLocationSentinel)
        XCTAssertEqual(store.state.content.homeFavoriteItems, homeFavoriteSentinel)

        let validSelectionState = store.state
        await store.send(.contentTabs(.toggleSelection(invalidTab)))
        XCTAssertEqual(store.state, validSelectionState)
        await store.send(.contentTabs(.selectRange(
            to: invalidTab,
            orderedIDs: store.state.contentTabSelectionOrderedIDs,
        )))
        XCTAssertEqual(store.state, validSelectionState)
    }

    /// CTM-001-select_content_tabs: drag snapshot은 표시 순서와 initiating membership을 고정한다.
    /// 선택된 row와 비선택 row에서 frozen batch 경계가 달라지는 계약을 검증한다.
    /// - 검증 내용: displayed-order stable dedup/source filter와 non-member singleton 준비
    /// - 사전 조건: storage A/B/C/D와 다른 표시 D/B/A/C/D/stale, 선택 D/B/stale
    /// - 기대 결과: D drag는 D/B를 고정하고 비선택 A drag는 A singleton이며 missing initiating은 거부된다.
    func testContentTabDragSnapshotUsesDisplayedOrderAndNonMemberSingleton() {
        let tabA = ContentTabID(rawValue: "drag-a")
        let tabB = ContentTabID(rawValue: "drag-b")
        let tabC = ContentTabID(rawValue: "drag-c")
        let tabD = ContentTabID(rawValue: "drag-d")
        let staleTab = ContentTabID(rawValue: "drag-stale")
        let sourceTabIDs = Set([tabA, tabB, tabC, tabD])
        let displayedOrder = [tabD, tabB, tabA, tabC, tabD, staleTab]
        let selectedTabIDs = Set([tabD, tabB, staleTab])

        XCTAssertEqual(
            ContentTabDragSnapshot.frozenOrderedTabIDs(
                initiatingTabID: tabD,
                selectedTabIDs: selectedTabIDs,
                displayedOrderedTabIDs: displayedOrder,
                sourceTabIDs: sourceTabIDs,
            ),
            [tabD, tabB],
        )
        XCTAssertEqual(
            ContentTabDragSnapshot.frozenOrderedTabIDs(
                initiatingTabID: tabA,
                selectedTabIDs: selectedTabIDs,
                displayedOrderedTabIDs: displayedOrder,
                sourceTabIDs: sourceTabIDs,
            ),
            [tabA],
        )
        XCTAssertNil(ContentTabDragSnapshot.frozenOrderedTabIDs(
            initiatingTabID: staleTab,
            selectedTabIDs: selectedTabIDs,
            displayedOrderedTabIDs: displayedOrder,
            sourceTabIDs: sourceTabIDs,
        ))
    }

    private enum ContentTabButtonRoute: Equatable {
        case activate
        case toggleSelection
        case selectRange
    }

    private enum ContentTabMenuAction: Equatable {
        case duplicate
        case pin
        case unpin
        case close
    }

    private final class ContentTabButtonRecorder {
        var routes: [ContentTabButtonRoute] = []
        var menuActions: [ContentTabMenuAction] = []
        var draggingItems: [[NSDraggingItem]] = []
        var dragStartEvents: [NSEvent] = []
    }

    private struct ContentTabButtonFixture {
        let window: NSWindow
        let button: ContentTabSidebarButton
        let recorder: ContentTabButtonRecorder
        let sessionStore: FileManagerTopNavigationReorderLocalSessionStore
    }

    private var insideButtonLocation: NSPoint {
        NSPoint(x: 24, y: 12)
    }

    private func withContentTabButtonFixture(
        recorder: ContentTabButtonRecorder = ContentTabButtonRecorder(),
        isPinned: Bool = false,
        _ body: (ContentTabButtonFixture) throws -> Void,
    ) rethrows {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )
        let contentView = NSView(frame: window.contentLayoutRect)
        let button = ContentTabSidebarButton(frame: NSRect(x: 20, y: 40, width: 240, height: 28))
        let sessionStore = FileManagerTopNavigationReorderLocalSessionStore()
        configure(
            button,
            recorder: recorder,
            sessionStore: sessionStore,
            isPinned: isPinned,
        )
        button.dragSessionStartOverride = { items, event in
            recorder.draggingItems.append(items)
            recorder.dragStartEvents.append(event)
            _ = window.nextEvent(
                matching: .leftMouseUp,
                until: .distantPast,
                inMode: .eventTracking,
                dequeue: true,
            )
        }
        contentView.addSubview(button)
        window.contentView = contentView
        window.orderFrontRegardless()
        Self.retainedAppKitWindows.append(window)
        let fixture = ContentTabButtonFixture(
            window: window,
            button: button,
            recorder: recorder,
            sessionStore: sessionStore,
        )

        defer {
            button.dismantle()
            window.orderOut(nil)
        }
        try body(fixture)
    }

    private func configure(
        _ button: ContentTabSidebarButton,
        recorder: ContentTabButtonRecorder,
        sessionStore: FileManagerTopNavigationReorderLocalSessionStore,
        sourceID: ContentTabID = ContentTabID(rawValue: "source"),
        rootView: AnyView = AnyView(Color.clear.frame(height: 24)),
        accessibilityValue: String = "Active, Not Selected",
        isPinned: Bool = false,
        isEnabled: Bool = true,
    ) {
        button.update(configuration: .init(
            rootView: rootView,
            accessibilityLabel: "Content Tab",
            accessibilityValue: accessibilityValue,
            duplicateAccessibilityIdentifier: "duplicate-content-tab-test",
            isPinned: isPinned,
            isEnabled: isEnabled,
            reorderDragSource: isPinned ? nil : FileManagerTopNavigationReorderDragSourceConfiguration(
                payload: .init(
                    sourceID: .contentTab(sourceID),
                    dragScopeID: FileManagerTopNavigationReorderDragScopeID(),
                ),
                sessionStore: sessionStore,
            ),
            onActivate: { recorder.routes.append(.activate) },
            onToggleSelection: { recorder.routes.append(.toggleSelection) },
            onSelectRange: { recorder.routes.append(.selectRange) },
            onDuplicate: { recorder.menuActions.append(.duplicate) },
            onPin: { recorder.menuActions.append(.pin) },
            onUnpin: { recorder.menuActions.append(.unpin) },
            onClose: { recorder.menuActions.append(.close) },
        ))
    }

    private func dispatchPrimaryClick(
        on button: ContentTabSidebarButton,
        modifiers: NSEvent.ModifierFlags,
    ) throws {
        let mouseDown = try mouseEvent(
            .leftMouseDown,
            on: button,
            modifiers: modifiers,
            locationInButton: insideButtonLocation,
            eventNumber: 1,
        )
        let mouseUp = try mouseEvent(
            .leftMouseUp,
            on: button,
            modifiers: modifiers,
            locationInButton: insideButtonLocation,
            eventNumber: 2,
        )
        NSApp.postEvent(mouseUp, atStart: true)
        button.mouseDown(with: mouseDown)
    }

    private func dispatchSubthresholdDragOutside(
        on button: ContentTabSidebarButton,
        modifiers: NSEvent.ModifierFlags,
    ) throws {
        let downLocation = NSPoint(x: button.bounds.maxX - 1, y: button.bounds.midY)
        let outsideLocation = NSPoint(x: button.bounds.maxX + 1, y: button.bounds.midY)
        let mouseDown = try mouseEvent(
            .leftMouseDown,
            on: button,
            modifiers: modifiers,
            locationInButton: downLocation,
            eventNumber: 1,
        )
        let mouseDragged = try mouseEvent(
            .leftMouseDragged,
            on: button,
            modifiers: modifiers,
            locationInButton: outsideLocation,
            eventNumber: 2,
        )
        let mouseUp = try mouseEvent(
            .leftMouseUp,
            on: button,
            modifiers: modifiers,
            locationInButton: outsideLocation,
            eventNumber: 3,
        )
        NSApp.postEvent(mouseDragged, atStart: true)
        NSApp.postEvent(mouseUp, atStart: false)
        button.mouseDown(with: mouseDown)
    }

    private func dispatchThresholdDrag(
        on button: ContentTabSidebarButton,
        modifiers: NSEvent.ModifierFlags,
    ) throws {
        let dragLocation = NSPoint(
            x: insideButtonLocation.x + 12,
            y: insideButtonLocation.y,
        )
        let mouseDown = try mouseEvent(
            .leftMouseDown,
            on: button,
            modifiers: modifiers,
            locationInButton: insideButtonLocation,
            eventNumber: 1,
        )
        let mouseDragged = try mouseEvent(
            .leftMouseDragged,
            on: button,
            modifiers: modifiers,
            locationInButton: dragLocation,
            eventNumber: 2,
        )
        let mouseUp = try mouseEvent(
            .leftMouseUp,
            on: button,
            modifiers: modifiers,
            locationInButton: dragLocation,
            eventNumber: 3,
        )
        NSApp.postEvent(mouseDragged, atStart: true)
        NSApp.postEvent(mouseUp, atStart: false)
        button.mouseDown(with: mouseDown)
    }

    private func dispatchPrimaryDragOutside(
        on button: ContentTabSidebarButton,
        modifiers: NSEvent.ModifierFlags,
    ) throws {
        let outsideLocation = NSPoint(x: button.bounds.maxX + 40, y: button.bounds.maxY + 40)
        let mouseDown = try mouseEvent(
            .leftMouseDown,
            on: button,
            modifiers: modifiers,
            locationInButton: insideButtonLocation,
            eventNumber: 1,
        )
        let mouseDragged = try mouseEvent(
            .leftMouseDragged,
            on: button,
            modifiers: modifiers,
            locationInButton: outsideLocation,
            eventNumber: 2,
        )
        let mouseUp = try mouseEvent(
            .leftMouseUp,
            on: button,
            modifiers: modifiers,
            locationInButton: outsideLocation,
            eventNumber: 3,
        )
        NSApp.postEvent(mouseDragged, atStart: true)
        NSApp.postEvent(mouseUp, atStart: false)
        button.mouseDown(with: mouseDown)
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        on button: ContentTabSidebarButton,
        modifiers: NSEvent.ModifierFlags,
        locationInButton: NSPoint,
        eventNumber: Int,
    ) throws -> NSEvent {
        let window = try XCTUnwrap(button.window)
        return try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: button.convert(locationInButton, to: nil),
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: eventNumber,
            clickCount: 1,
            pressure: 1,
        ))
    }

    private func makeWindowSelectionSentinelState(
        tabA: ContentTabID,
        tabB: ContentTabID,
        stalePendingTab: ContentTabID,
    ) -> FileManagerFeature.State {
        let sourceLocation = FileManagerFixedLocationItem(
            id: "source-location",
            title: "Source Location",
            path: "/source/location",
            iconName: "folder",
            accessibilityLabel: "Source Location",
        )
        let preservedLocation = FileManagerFixedLocationItem(
            id: "preserved-location",
            title: "Preserved Location",
            path: "/preserved/location",
            iconName: "folder",
            accessibilityLabel: "Preserved Location",
        )
        let sourceFavorite = FileManagerHomeFavoriteItem(
            id: ContentTabID(rawValue: "source-favorite"),
            title: "Source Favorite",
            iconName: "folder",
            filePath: "/source/favorite",
            anchor: .directory(path: "/source/favorite"),
            page: .directory,
        )
        let preservedFavorite = FileManagerHomeFavoriteItem(
            id: ContentTabID(rawValue: "preserved-favorite"),
            title: "Preserved Favorite",
            iconName: "folder",
            filePath: "/preserved/favorite",
            anchor: .directory(path: "/preserved/favorite"),
            page: .directory,
        )
        let sidebarSentinel = Self.sidebarSentinel()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [tab(id: tabA, isPinned: false), tab(id: tabB, isPinned: true)],
            activeTabID: tabA,
            previousActiveTabID: tabB,
        )
        state.pendingDirectoryReloadTabIDs = [tabB, stalePendingTab]
        state.applyFixedLocationItems([sourceLocation])
        state.content.homeLocationItems = [preservedLocation]
        state.applyHomeFavoriteItems([sourceFavorite])
        state.content.homeFavoriteItems = [preservedFavorite]
        state.sidebar.contentTabSidebarItems = [sidebarSentinel]
        return state
    }

    private static func sidebarSentinel() -> ContentTabProjection.ContentTabSidebarItem {
        ContentTabProjection.ContentTabSidebarItem(
            id: ContentTabID(rawValue: "sidebar-sentinel"),
            title: "Sidebar Sentinel",
            iconName: "star",
            targetURL: nil,
            tagColorCode: 451,
            pageType: .home,
            isActive: false,
            isPinned: true,
        )
    }

    private func tab(id: ContentTabID, isPinned: Bool) -> ContentTabItem {
        ContentTabItem(
            id: id,
            page: .directory,
            anchor: .directory(path: "/\(id.rawValue)"),
            isPinned: isPinned,
            title: id.rawValue,
            iconName: "folder",
        )
    }
}
