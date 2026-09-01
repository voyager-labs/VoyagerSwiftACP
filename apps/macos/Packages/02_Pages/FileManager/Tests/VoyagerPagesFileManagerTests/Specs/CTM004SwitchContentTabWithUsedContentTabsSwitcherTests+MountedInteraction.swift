import AppKit
import ComposableArchitecture
import Foundation
import PerceptionCore
import SwiftUI
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

extension CTM004SwitchContentTabWithUsedContentTabsSwitcherTests {
    // MARK: - CTM-004-present_focused_candidate

    /// CTM-004-present_focused_candidate: focus된 non-current card가 Current와 독립된 시각·접근성 상태를 유지한다.
    /// reducer가 선택한 ContentTabID가 실제 SwiftUI row focus와 분리된 Current metadata를 구동하는 계약을 검증한다.
    /// - 검증 내용: reducer focus identity 매핑, row focus ring(reducer state 전용), native focus 경쟁 부재, 기존 accessibility
    /// metadata 보존
    /// - 사전 조건: current card와 별도의 focused candidate가 있는 automatic switcher, deterministic FileManagerHost fixture
    /// - 기대 결과: focused non-current와 Current가 동시에 구분되고 activation/tap callback 없이 동일한 row identifier/label/value를 사용한다.
    @MainActor
    func testFocusedCandidateVisualAndAccessibilityRemainDistinctFromCurrent() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let presentationSource = try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/VoyagerPagesFileManager/Window/Model/FileManagerContentTabSwitcherPresentation.swift",
            ),
            encoding: .utf8,
        )
        let viewSource = try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/VoyagerPagesFileManager/Window/Ui/FileManagerContentTabSwitcherView.swift",
            ),
            encoding: .utf8,
        )
        let state = makeState(
            tabs: [
                tab("current", title: "Current Tab", icon: "house"),
                tab("candidate", title: "Focused Candidate", icon: "folder"),
            ],
            active: "current",
            mru: ["candidate", "current"],
        )
        let contentTabsBeforeFocus = state
        guard case let .content(rows) = ContentTabSwitcherViewState.make(
            source: .automatic,
            contentTabs: state,
            focusedCandidateID: id("candidate"),
        ) else {
            return XCTFail("Expected focused candidate content rows")
        }
        guard case let .content(focusedCurrentRows) = ContentTabSwitcherViewState.make(
            source: .automatic,
            contentTabs: state,
            focusedCandidateID: id("current"),
        ) else {
            return XCTFail("Expected focused-current content rows")
        }
        try assertFocusedCandidateViewContract(
            presentationSource: presentationSource,
            viewSource: viewSource,
            rows: rows,
            focusedCurrentRows: focusedCurrentRows,
            contentTabs: state,
            contentTabsBeforeFocus: contentTabsBeforeFocus,
        )
    }

    /// CTM-004-present_focused_candidate: Tab 탐색 경계에서 repeat·명령 조합·Shift 수정 다른 키·IME 조합은 focus를 만들지
    /// 않는다.
    /// 거부 입력 후 정상 Tab이 여전히 동작해 guard가 과다 거부하지 않는지도 검증한다.
    /// - 검증 내용: isARepeat/Cmd/Ctrl/Option+Tab과 Shift+방향키 0회 focus, marked text 중 Tab 무시, 이후 정상 Tab 1회 focus,
    /// confirm·dismiss 0회
    /// - 사전 조건: non-current focused row를 가진 2-candidate content view state의 독립적인 fresh NSHostingController window
    /// - 기대 결과: 모든 거부 입력은 callback을 만들지 않고 마지막 정상 Tab만 focus를 candidate에서 current로 이동한다.
    @MainActor
    func testMountedTabTraversalRejectsRepeatModifiedAndMarkedTextInputs() async throws {
        let setup = try await makeFocusedCandidateMountedSwitcher()
        defer { teardownMountedSwitcher(setup.mounted) }
        let window = setup.mounted.window

        sendBridgeTab(window: window, characters: "\t", isARepeat: true)
        await assertTraversal(setup, expected: [], label: "repeat-tab-rejected")
        for modifiers: NSEvent.ModifierFlags in [.command, .control, .option] {
            sendBridgeTab(window: window, modifiers: modifiers, characters: "\t")
        }
        let shiftArrowEvent = try keyDownEvent(
            window: window,
            keyCode: 124,
            modifiers: [.shift],
            characters: "\u{f703}",
            charactersIgnoringModifiers: "\u{f703}",
        )
        window.sendEvent(shiftArrowEvent)
        await assertTraversal(setup, expected: [], label: "modified-inputs-rejected")

        // IME marked text 중 Tab은 입력기가 소유한다.
        let bridge = try XCTUnwrap(keyCommandView(in: setup.mounted.hostingController.view))
        bridge.setMarkedText(
            "가",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )
        sendBridgeTab(window: window, characters: "\t")
        bridge.cancelMarkedTextComposition()
        await assertTraversal(setup, expected: [], label: "marked-text-tab-rejected")

        // 정상 Tab은 여전히 1회 forward 이동한다.
        sendBridgeTab(window: window, characters: "\t")
        await assertTraversal(setup, expected: [.next], label: "plain-tab-still-works")
    }

    /// CTM-004-present_focused_candidate: 비반복 Tab ×3과 Shift+Tab ×2의 개별 keyDown이 매 이벤트마다 정확히 1회씩
    /// forward/backward로 이동하고 양방향에서 wrap하며, isARepeat Tab은 별도 단일 거부 단계에서 시퀀스를 변경하지 않는다.
    /// - 검증 내용: 비반복 Tab forward/wrap 시퀀스 [current, candidate, current], Shift+Tab backward/wrap 시퀀스
    /// [current, candidate, current, candidate, current], isARepeat Tab 1회 0 이동, 매 이벤트 후 first responder 유지,
    /// confirm·dismiss 0회
    /// - 사전 조건: non-current focused row를 가진 2-candidate content view state의 독립적인 fresh NSHostingController window
    /// - 기대 결과: callback 시퀀스가 위 ID 목록과 정확히 일치하고 모든 이벤트 후에도 bridge가 first responder이다.
    @MainActor
    func testMountedTabPressesTraverseBothDirectionsWithWrapAndRepeatIsRejected() async throws {
        let setup = try await makeFocusedCandidateMountedSwitcher()
        defer { teardownMountedSwitcher(setup.mounted) }
        let window = setup.mounted.window

        let forwardExpectations = [
            [ContentTabSwitcherFocusDirection.next],
            [.next, .next],
            [.next, .next, .next],
        ]
        for (step, expected) in forwardExpectations.enumerated() {
            sendBridgeTab(window: window, characters: "\t")
            await assertTraversal(setup, expected: expected, label: "tab-forward-\(step + 1)")
        }

        // isARepeat Tab은 사용자 반복 입력이 아니라 별도 단일 거부 단계로 검증한다.
        sendBridgeTab(window: window, characters: "\t", isARepeat: true)
        await assertTraversal(setup, expected: forwardExpectations[2], label: "repeat-tab-rejected")

        // Shift+Tab ×2: current → candidate → current(backward 방향 이동)
        var backwardState = forwardExpectations[2]
        for step in 1 ... 2 {
            sendBridgeTab(window: window, modifiers: [.shift], characters: "\u{0019}")
            backwardState.append(.previous)
            await assertTraversal(setup, expected: backwardState, label: "shift-tab-backward-\(step)")
        }
    }

    // MARK: - CTM-004-confirm_content_tab_switcher_input

    /// CTM-004-confirm_content_tab_switcher_input: 실제 keypad event와 Escape event는 overlay-local bridge가 소유한다.
    /// 수동 `makeFirstResponder`나 `performKeyEquivalent` 우회 없이 window activation만으로 first responder를 확보한 뒤 실제
    /// keyDown을 전달해 focused row 활성화와 dismiss 경계를 검증한다.
    /// - 검증 내용: 자연 first responder 획득, key code 36 Return의 1회 focused row 활성화, key code 76 keypad Enter의 문자 무관
    /// 1회 활성화,
    /// key code 53 Escape의 1회 dismiss, 방향키 focus 이동
    /// - 사전 조건: focused non-current content state와 독립적인 fresh NSHostingController window
    /// - 기대 결과: bridge가 first responder인 상태에서 각 입력이 정확히 한 번씩 semantic callback을 호출한다.
    @MainActor
    func testMountedRealKeypadAndEscapeEventsRequireOverlayBridge() async throws {
        _ = NSApplication.shared
        NSApp.activate(ignoringOtherApps: true)
        let contentTabs = makeState(
            tabs: [tab("current"), tab("candidate")],
            active: "current",
            mru: ["candidate", "current"],
        )
        guard case let .content(rows) = ContentTabSwitcherViewState.make(
            source: .automatic,
            contentTabs: contentTabs,
            focusedCandidateID: id("candidate"),
        ) else {
            return XCTFail("Expected content view state")
        }
        var activationCount = 0
        var dismissCount = 0
        var focusChanges: [ContentTabSwitcherFocusDirection] = []
        let mounted = makeMountedSwitcherWindow(
            viewState: .content(rows),
            onFocusMove: { focusChanges.append($0) },
            onActivate: { _ in activationCount += 1 },
            onDismiss: { dismissCount += 1 },
        )
        defer { teardownMountedSwitcher(mounted) }
        await drainMainQueue()
        mounted.window.makeKeyAndOrderFront(nil)
        _ = try await waitUntilBridgeIsFirstResponder(in: mounted)

        let returnEvent = try keyDownEvent(window: mounted.window, keyCode: 36, modifiers: [])
        mounted.window.sendEvent(returnEvent)
        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(dismissCount, 0)

        let keypadEvent = try keyDownEvent(
            window: mounted.window,
            keyCode: 76,
            modifiers: [],
            characters: "\u{0003}",
            charactersIgnoringModifiers: "\u{0003}",
        )
        mounted.window.sendEvent(keypadEvent)
        XCTAssertEqual(activationCount, 2)
        XCTAssertEqual(dismissCount, 0)

        let escapeEvent = try keyDownEvent(
            window: mounted.window,
            keyCode: 53,
            modifiers: [],
            characters: "\u{001b}",
            charactersIgnoringModifiers: "\u{001b}",
        )
        mounted.window.sendEvent(escapeEvent)
        XCTAssertEqual(activationCount, 2)
        XCTAssertEqual(dismissCount, 1)

        let rightArrowEvent = try keyDownEvent(
            window: mounted.window,
            keyCode: 124,
            modifiers: [],
            characters: "\u{f703}",
            charactersIgnoringModifiers: "\u{f703}",
        )
        mounted.window.sendEvent(rightArrowEvent)
        XCTAssertEqual(focusChanges, [.next])
    }

    /// CTM-004-confirm_content_tab_switcher_input: window 활성화와 view state 갱신 후에도 bridge가 first responder를 유지한다.
    /// activation feedback 루프나 native focus 재동기화가 bridge를 single first responder slot에서 밀어내는 displacement 회귀를
    /// 검증한다.
    /// - 검증 내용: 자연 first responder 획득, window 재활성화 후 유지, view state(focus identity) 변경 후 유지
    /// - 사전 조건: focused non-current content state와 독립적인 fresh NSHostingController window
    /// - 기대 결과: 모든 시점에 `window.firstResponder`가 KeyCommandHostingView이다.
    @MainActor
    func testWindowActivationAndViewStateChangesPreserveBridgeFirstResponder() async throws {
        _ = NSApplication.shared
        NSApp.activate(ignoringOtherApps: true)
        let contentTabs = makeState(
            tabs: [tab("current"), tab("candidate")],
            active: "current",
            mru: ["candidate", "current"],
        )
        guard case let .content(rows) = ContentTabSwitcherViewState.make(
            source: .automatic,
            contentTabs: contentTabs,
            focusedCandidateID: id("candidate"),
        ) else {
            return XCTFail("Expected content view state")
        }
        let mounted = makeMountedSwitcherWindow(
            viewState: .content(rows),
            onDismiss: {},
        )
        defer { teardownMountedSwitcher(mounted) }
        await drainMainQueue()
        mounted.window.makeKeyAndOrderFront(nil)
        _ = try await waitUntilBridgeIsFirstResponder(in: mounted)

        mounted.window.makeKeyAndOrderFront(nil)
        await drainMainQueue()
        await drainMainQueue()
        XCTAssertTrue(mounted.window.firstResponder is KeyCommandHostingView)

        guard case let .content(refocusedRows) = ContentTabSwitcherViewState.make(
            source: .automatic,
            contentTabs: contentTabs,
            focusedCandidateID: id("current"),
        ) else {
            return XCTFail("Expected refocused content rows")
        }
        mounted.hostingController.rootView = FileManagerContentTabSwitcherView(
            viewState: .content(refocusedRows),
            onDismiss: {},
        )
        await drainMainQueue()
        await drainMainQueue()
        XCTAssertTrue(mounted.window.firstResponder is KeyCommandHostingView)
    }

    /// CTM-004-confirm_content_tab_switcher_input: 조건부 switcher가 해제되면 기존 content key-command responder를 복원한다.
    /// 실제 main container의 overlay mount/unmount 후 coordinator가 등록된 persistent content bridge를 다시 소유하는지 검증한다.
    /// - 검증 내용: content bridge A → overlay bridge B → overlay detach → content bridge A first responder 복원
    /// - 사전 조건: switcher 미표시 main container와 동일 coordinator에 등록된 content KeyCommandHostingView
    /// - 기대 결과: 해제 다음 main run loop에 content bridge가 window first responder를 되찾는다.
    @MainActor
    func testUnmountingContentTabSwitcherRestoresExistingContentBridgeOnNextMainRunLoop() async throws {
        _ = NSApplication.shared
        let perceptionCheckingWasEnabled = PerceptionCore.isPerceptionCheckingEnabled
        PerceptionCore.isPerceptionCheckingEnabled = false
        defer { PerceptionCore.isPerceptionCheckingEnabled = perceptionCheckingWasEnabled }
        var initialState = makeSwitcherWindowState(prefix: "focus-restore")
        initialState.contentTabSwitcherPresentation = nil
        let store = Store(initialState: initialState) {
            FileManagerFeature()
        }
        let focusCoordinator = FileManagerKeyCommandFocusCoordinator()
        let hostingController = NSHostingController(
            rootView: WithViewStore(store, observe: { $0.contentTabSwitcherPresentation != nil }) { _ in
                FileManagerWindowMainContainerView(
                    store: store,
                    isDark: false,
                    materialOverride: nil,
                    keyCommandFocusCoordinator: focusCoordinator,
                )
            },
        )
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 960, height: 510))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
        }

        let contentBridge = try await waitUntilContentBridgeIsAttached(in: hostingController.view)
        XCTAssertTrue(window.makeFirstResponder(contentBridge))

        store.send(.request(.presentContentTabSwitcher(source: .automatic)))
        let overlayBridge = try await waitUntilOverlayBridgeIsAttached(
            in: hostingController.view,
            excluding: contentBridge,
        )
        XCTAssertTrue(window.makeFirstResponder(overlayBridge))
        XCTAssertIdentical(window.firstResponder, overlayBridge)

        store.send(.view(.dismissContentTabSwitcher))
        XCTAssertNil(store.withState { $0.contentTabSwitcherPresentation })
        for _ in 0 ..< 20 where window.firstResponder !== contentBridge {
            hostingController.view.needsLayout = true
            hostingController.view.layoutSubtreeIfNeeded()
            await drainMainQueue()
        }

        XCTAssertIdentical(contentBridge.window, window)
        XCTAssertIdentical(window.firstResponder, contentBridge)
    }

    /// CTM-004-confirm_content_tab_switcher_input: mounted default action이 허용 입력과 거부 입력을 정확히 분리한다.
    /// 실제 NSHostingController 안에서 fresh switcher를 반복 생성해 Return 계열과 modifier·IME·status semantics를 검증한다.
    /// - 검증 내용: unmodified Return/keypad Enter 1회 확인, Command/Control/Option·marked text·loading/empty/error 0회 확인
    /// - 사전 조건: non-current focused row를 가진 content view state와 각 입력별 독립 NSWindow
    /// - 기대 결과: content 상태에서 허용된 두 키만 callback을 한 번 호출하고 모든 거부 입력은 callback을 호출하지 않는다.
    @MainActor
    func testMountedDefaultActionInputMatrix() async throws {
        _ = NSApplication.shared
        NSApp.activate(ignoringOtherApps: true)
        let contentTabs = makeState(
            tabs: [tab("current"), tab("candidate")],
            active: "current",
            mru: ["candidate", "current"],
        )
        guard case let .content(rows) = ContentTabSwitcherViewState.make(
            source: .automatic,
            contentTabs: contentTabs,
            focusedCandidateID: id("candidate"),
        ) else {
            return XCTFail("Expected content view state")
        }
        for inputCase in MountedDefaultActionInputCase.contentCases {
            try await assertMountedInputCase(inputCase, viewState: .content(rows))
        }

        let statusStates: [(String, ContentTabSwitcherViewState)] = [
            ("loading", .loading(.init(message: "Loading", accessibilityLabel: "Loading"))),
            ("empty", .empty(.init(message: "Empty", accessibilityLabel: "Empty"))),
            ("error", .error(.init(message: "Error", accessibilityLabel: "Error"))),
        ]
        for (name, viewState) in statusStates {
            try await assertMountedStatusInput(name: name, viewState: viewState)
        }
    }

    @MainActor
    private func assertMountedInputCase(
        _ inputCase: MountedDefaultActionInputCase,
        viewState: ContentTabSwitcherViewState,
    ) async throws {
        var confirmationCount = 0
        let mounted = makeMountedSwitcherWindow(
            viewState: viewState,
            onActivate: { _ in confirmationCount += 1 },
        )
        defer { teardownMountedSwitcher(mounted) }
        await drainMainQueue()
        mounted.window.makeKeyAndOrderFront(nil)
        let keyCommandView = try await waitUntilBridgeIsFirstResponder(in: mounted)

        if let markedText = inputCase.markedText {
            // IME 조합 상태는 bridge 자체의 NSTextInputClient 세션으로 시뮬레이션한다.
            keyCommandView.setMarkedText(
                markedText,
                selectedRange: NSRange(location: markedText.utf16.count, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0),
            )
        }

        let event = try keyDownEvent(
            window: mounted.window,
            keyCode: inputCase.keyCode,
            modifiers: inputCase.modifiers,
            characters: inputCase.characters,
            charactersIgnoringModifiers: inputCase.charactersIgnoringModifiers,
            isARepeat: inputCase.isARepeat,
        )
        mounted.window.sendEvent(event)
        XCTAssertEqual(confirmationCount, inputCase.expectsConfirmation ? 1 : 0, inputCase.name)

        if inputCase.markedText != nil {
            keyCommandView.cancelMarkedTextComposition()
        }
    }

    @MainActor
    private func assertMountedStatusInput(
        name: String,
        viewState: ContentTabSwitcherViewState,
    ) async throws {
        var confirmationCount = 0
        let mounted = makeMountedSwitcherWindow(
            viewState: viewState,
            onActivate: { _ in confirmationCount += 1 },
        )
        defer { teardownMountedSwitcher(mounted) }
        await drainMainQueue()
        mounted.window.makeKeyAndOrderFront(nil)
        _ = try await waitUntilBridgeIsFirstResponder(in: mounted)
        let event = try keyDownEvent(window: mounted.window, keyCode: 36, modifiers: [])
        mounted.window.sendEvent(event)
        XCTAssertEqual(confirmationCount, 0, name)
    }

    /// non-current focused candidate를 가진 fresh mounted switcher window를 만들고 bridge first responder를 기다린다.
    @MainActor
    private func makeFocusedCandidateMountedSwitcher() async throws -> FocusedCandidateMountedSwitcherSetup {
        _ = NSApplication.shared
        NSApp.activate(ignoringOtherApps: true)
        let contentTabs = makeState(
            tabs: [tab("current"), tab("candidate")],
            active: "current",
            mru: ["candidate", "current"],
        )
        guard case let .content(rows) = ContentTabSwitcherViewState.make(
            source: .automatic,
            contentTabs: contentTabs,
            focusedCandidateID: id("candidate"),
        ) else {
            throw SwitcherSetupError.missingContentRows
        }
        let recorder = SwitcherInputRecorder()
        let mounted = makeMountedSwitcherWindow(
            viewState: .content(rows),
            onFocusMove: { recorder.focusDirections.append($0) },
            onActivate: { _ in recorder.confirmationCount += 1 },
            onDismiss: { recorder.dismissCount += 1 },
        )
        await drainMainQueue()
        mounted.window.makeKeyAndOrderFront(nil)
        _ = try await waitUntilBridgeIsFirstResponder(in: mounted)
        return FocusedCandidateMountedSwitcherSetup(mounted: mounted, contentTabs: contentTabs, recorder: recorder)
    }

    /// bridge로 keyCode 48 keyDown을 전달한다.
    @MainActor
    private func sendBridgeTab(
        window: NSWindow,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String,
        isARepeat: Bool = false,
        line: UInt = #line,
    ) {
        let event = try? keyDownEvent(
            window: window,
            keyCode: 48,
            modifiers: modifiers,
            characters: characters,
            charactersIgnoringModifiers: "\t",
            isARepeat: isARepeat,
        )
        if let event {
            window.sendEvent(event)
        } else {
            XCTFail("Expected Tab keyDown event", line: line)
        }
    }

    /// focus 시퀀스·first responder·무 activation 경계를 검증한다.
    @MainActor
    private func assertTraversal(
        _ setup: FocusedCandidateMountedSwitcherSetup,
        expected: [ContentTabSwitcherFocusDirection],
        label: String,
        line: UInt = #line,
    ) async {
        XCTAssertEqual(setup.recorder.focusDirections, expected, label, line: line)
        for _ in 0 ..< 20 where !(setup.mounted.window.firstResponder is KeyCommandHostingView) {
            await drainMainQueue()
        }
        XCTAssertTrue(
            setup.mounted.window.firstResponder is KeyCommandHostingView,
            "\(label): first responder 유지",
            line: line,
        )
        XCTAssertEqual(setup.recorder.confirmationCount, 0, label, line: line)
        XCTAssertEqual(setup.recorder.dismissCount, 0, label, line: line)
    }

    @MainActor
    private func waitUntilBridgeIsFirstResponder(in mounted: MountedSwitcherWindow) async throws
        -> KeyCommandHostingView
    {
        let bridge = try XCTUnwrap(keyCommandView(in: mounted.hostingController.view))
        for _ in 0 ..< 20 where mounted.window.firstResponder !== bridge {
            await drainMainQueue()
        }
        if mounted.window.firstResponder !== bridge {
            XCTFail(
                "Expected overlay-local KeyCommandHostingView as first responder, got \(mounted.window.firstResponder)",
            )
        }
        return bridge
    }

    @MainActor
    private func waitUntilOverlayBridgeIsAttached(
        in rootView: NSView,
        excluding contentBridge: KeyCommandHostingView,
    ) async throws -> KeyCommandHostingView {
        for _ in 0 ..< 40 {
            if let overlayBridge = keyCommandViews(in: rootView).first(where: { $0 !== contentBridge }) {
                return overlayBridge
            }
            await drainMainQueue()
        }
        XCTFail("Overlay KeyCommandHostingView did not attach")
        throw SwitcherSetupError.missingOverlayBridge
    }

    @MainActor
    private func waitUntilContentBridgeIsAttached(in rootView: NSView) async throws -> KeyCommandHostingView {
        for _ in 0 ..< 40 {
            if let contentBridge = keyCommandViews(in: rootView).first {
                return contentBridge
            }
            await drainMainQueue()
        }
        XCTFail("Persistent content KeyCommandHostingView did not attach")
        throw SwitcherSetupError.missingOverlayBridge
    }

    @MainActor
    private func makeMountedSwitcherWindow(
        viewState: ContentTabSwitcherViewState,
        onFocusMove: @escaping (ContentTabSwitcherFocusDirection) -> Void = { _ in },
        onActivate: @escaping (ContentTabID) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {},
    ) -> MountedSwitcherWindow {
        let hostingController = NSHostingController(
            rootView: FileManagerContentTabSwitcherView(
                viewState: viewState,
                onFocusMove: onFocusMove,
                onActivate: onActivate,
                onDismiss: onDismiss,
            ),
        )
        let containerController = NSViewController()
        containerController.view = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 510))
        containerController.addChild(hostingController)
        hostingController.view.frame = containerController.view.bounds
        containerController.view.addSubview(hostingController.view)
        let window = NSWindow(contentViewController: containerController)
        window.makeKeyAndOrderFront(nil)
        return MountedSwitcherWindow(window: window, hostingController: hostingController)
    }

    @MainActor
    private func teardownMountedSwitcher(_ mounted: MountedSwitcherWindow) {
        mounted.window.orderOut(nil)
        mounted.window.contentViewController = nil
        mounted.hostingController.removeFromParent()
    }

    @MainActor
    private func keyDownEvent(
        window: NSWindow,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String = "\r",
        charactersIgnoringModifiers: String = "\r",
        isARepeat: Bool = false,
    ) throws -> NSEvent {
        let windowNumber = window.windowNumber
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 1,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: isARepeat,
            keyCode: keyCode,
        ))
    }

    @MainActor
    private func keyCommandView(in view: NSView) -> KeyCommandHostingView? {
        if let keyCommandView = view as? KeyCommandHostingView { return keyCommandView }
        for subview in view.subviews {
            if let keyCommandView = keyCommandView(in: subview) { return keyCommandView }
        }
        return nil
    }

    @MainActor
    private func keyCommandViews(in view: NSView) -> [KeyCommandHostingView] {
        let current = (view as? KeyCommandHostingView).map { [$0] } ?? []
        return current + view.subviews.flatMap(keyCommandViews(in:))
    }
}

/// Tab 탐색 테스트의 callback 기록 상자. 값 캡처 대신 참조로 최신 시퀀스를 공유한다.
private final class SwitcherInputRecorder {
    var focusDirections: [ContentTabSwitcherFocusDirection] = []
    var confirmationCount = 0
    var dismissCount = 0
}

private enum SwitcherSetupError: Swift.Error {
    case missingContentRows
    case missingOverlayBridge
}

private struct FocusedCandidateMountedSwitcherSetup {
    let mounted: MountedSwitcherWindow
    let contentTabs: ContentTabState
    let recorder: SwitcherInputRecorder
}

private struct MountedDefaultActionInputCase {
    let name: String
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let characters: String
    let charactersIgnoringModifiers: String
    let expectsConfirmation: Bool
    let markedText: String?
    var isARepeat = false
}

private extension MountedDefaultActionInputCase {
    static let contentCases = [
        Self(
            name: "return",
            keyCode: 36,
            modifiers: [],
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            expectsConfirmation: true,
            markedText: nil,
        ),
        Self(
            name: "keypad-enter",
            keyCode: 76,
            modifiers: [],
            characters: "\u{0003}",
            charactersIgnoringModifiers: "\u{0003}",
            expectsConfirmation: true,
            markedText: nil,
        ),
        Self(
            name: "keypad-enter-return-characters",
            keyCode: 76,
            modifiers: [],
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            expectsConfirmation: true,
            markedText: nil,
        ),
        Self(
            name: "command-return",
            keyCode: 36,
            modifiers: [.command],
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            expectsConfirmation: false,
            markedText: nil,
        ),
        Self(
            name: "control-return",
            keyCode: 36,
            modifiers: [.control],
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            expectsConfirmation: false,
            markedText: nil,
        ),
        Self(
            name: "option-return",
            keyCode: 36,
            modifiers: [.option],
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            expectsConfirmation: false,
            markedText: nil,
        ),
        Self(
            name: "shift-return",
            keyCode: 36,
            modifiers: [.shift],
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            expectsConfirmation: false,
            markedText: nil,
        ),
        Self(
            name: "repeated-return",
            keyCode: 36,
            modifiers: [],
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            expectsConfirmation: false,
            markedText: nil,
            isARepeat: true,
        ),
        Self(
            name: "ime-return",
            keyCode: 36,
            modifiers: [],
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            expectsConfirmation: false,
            markedText: "ㅎ",
        ),
    ]
}

private struct MountedSwitcherWindow {
    let window: NSWindow
    let hostingController: NSHostingController<FileManagerContentTabSwitcherView>
}

private func assertFocusedCandidateViewContract(
    presentationSource: String,
    viewSource: String,
    rows: [ContentTabSwitcherViewState.Row],
    focusedCurrentRows: [ContentTabSwitcherViewState.Row],
    contentTabs: ContentTabState,
    contentTabsBeforeFocus: ContentTabState,
) throws {
    let focusedRow = try XCTUnwrap(rows.first(where: { $0.id == id("candidate") }))
    let currentRow = try XCTUnwrap(rows.first(where: { $0.id == id("current") }))
    let focusedCurrentRow = try XCTUnwrap(focusedCurrentRows.first(where: { $0.id == id("current") }))
    let nonCurrentRow = try XCTUnwrap(focusedCurrentRows.first(where: { $0.id == id("candidate") }))

    XCTAssertTrue(presentationSource.contains("let isFocused: Bool"))
    XCTAssertFalse(viewSource.contains("@FocusState"))
    XCTAssertFalse(viewSource.contains(".focused("))
    XCTAssertFalse(viewSource.contains(".focusSection()"))
    XCTAssertFalse(viewSource.contains(".focusable()"))
    XCTAssertTrue(viewSource.contains("VStack(alignment: .center"))
    XCTAssertTrue(viewSource.contains("multilineTextAlignment(.center)"))
    XCTAssertFalse(viewSource.contains("row.pageLabel"))
    XCTAssertFalse(viewSource.contains("row.anchorSummary"))
    XCTAssertTrue(viewSource.contains("if row.isFocused"))
    XCTAssertTrue(viewSource.contains("VoyagerDS.BrandPrimaryColor.c500"))
    XCTAssertTrue(focusedRow.isFocused && !focusedRow.isCurrent)
    XCTAssertTrue(!currentRow.isFocused && currentRow.isCurrent)
    XCTAssertEqual(focusedRow.accessibilityIdentifier, "file-manager.content-tab-switcher.row.candidate")
    XCTAssertEqual(focusedRow.accessibilityLabel, "Focused Candidate")
    XCTAssertEqual(focusedRow.accessibilityValue, "Home; Home")
    XCTAssertEqual(currentRow.accessibilityIdentifier, "file-manager.content-tab-switcher.row.current")
    XCTAssertEqual(currentRow.accessibilityLabel, "Current Tab")
    XCTAssertEqual(currentRow.accessibilityValue, "Home; Home; Current")
    XCTAssertTrue(rows.allSatisfy(\.isIconAccessibilityHidden))

    XCTAssertTrue(focusedCurrentRow.isFocused && focusedCurrentRow.isCurrent)
    XCTAssertFalse(nonCurrentRow.isFocused || nonCurrentRow.isCurrent)
    XCTAssertEqual(
        [focusedCurrentRow.accessibilityIdentifier, focusedCurrentRow.accessibilityLabel,
         focusedCurrentRow.accessibilityValue],
        [currentRow.accessibilityIdentifier, currentRow.accessibilityLabel, currentRow.accessibilityValue],
    )
    XCTAssertNotEqual(rows.map(\.isFocused), focusedCurrentRows.map(\.isFocused))
    XCTAssertEqual(rows.map(\.id), focusedCurrentRows.map(\.id))
    XCTAssertEqual(rows.map(\.title), focusedCurrentRows.map(\.title))
    XCTAssertEqual(rows.map(\.accessibilityValue), focusedCurrentRows.map(\.accessibilityValue))
    XCTAssertEqual(contentTabs.tabs, contentTabsBeforeFocus.tabs)
    XCTAssertEqual(contentTabs.activeTabID, contentTabsBeforeFocus.activeTabID)
    XCTAssertEqual(contentTabs.recentlyUsedTabIDs, contentTabsBeforeFocus.recentlyUsedTabIDs)
    XCTAssertEqual(contentTabs.selectedTabIDs, contentTabsBeforeFocus.selectedTabIDs)

    let statusStates = [
        ContentTabSwitcherViewState.make(source: .loading, contentTabs: contentTabs),
        ContentTabSwitcherViewState.make(source: .error(message: "Host failure"), contentTabs: contentTabs),
        ContentTabSwitcherViewState.make(
            source: .automatic,
            contentTabs: makeState(tabs: [], active: nil, mru: []),
        ),
    ]
    XCTAssertFalse(statusStates.contains { state in
        if case .content = state { return true }
        return false
    })

    let rowSource = (viewSource.components(separatedBy: "private struct SwitcherRow: View").last ?? "")
        .components(separatedBy: "private struct ContentTabSwitcherKeyCommandBridge").first ?? ""
    for forbiddenToken in ["Button(", ".onTapGesture", ".onHover", "onActivate", "selection"] {
        XCTAssertFalse(rowSource.contains(forbiddenToken), forbiddenToken)
    }
    for forbiddenToken in ["setCurrent", "moveContentTabSwitcherFocus", ".send("] {
        XCTAssertFalse(viewSource.contains(forbiddenToken), forbiddenToken)
    }
}
