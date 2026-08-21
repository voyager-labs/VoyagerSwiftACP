import AppKit
import Carbon.HIToolbox
@testable import Voyager
import VoyagerPagesFileManager
import XCTest

@MainActor
final class CTM004SwitchContentTabWithUsedContentTabsSwitcherTests: XCTestCase {
    // MARK: - CTM-004-switch_content_tab_via_used_content_tabs_switcher

    func testAppDelegateSemanticCommandsMapExactlyToMenuCommands() {
        let cases: [(
            AppKeyboardShortcutMonitor.ControlTabGestureCommand,
            MenuCommandItem.AppCommand,
        )] = [
            (.immediateMostRecentlyUsed, .selectMostRecentlyUsedContentTab),
            (.presentSwitcher, .presentContentTabSwitcher),
            (.moveNext, .moveNextContentTabSwitcher),
            (.movePrevious, .movePreviousContentTabSwitcher),
            (.dismissSwitcher, .dismissContentTabSwitcher),
        ]

        for (input, expected) in cases {
            XCTAssertEqual(AppDelegate.menuCommand(for: input), expected)
        }
    }

    /// CTM-004-short_hold_arbitration: 249ms release emits one immediate MRU command.
    func testControlTabShortReleaseEmitsImmediateOnceAt249Milliseconds() {
        let fixture = MonitorFixture()
        XCTAssertNil(fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
        ))
        XCTAssertNil(fixture.monitor.handleKeyUpEvent(
            fixture.event(.keyUp, timestamp: 10.249),
            context: fixture.context,
            emit: fixture.emit,
        ))

        XCTAssertEqual(fixture.commands, [.immediateMostRecentlyUsed])
    }

    func testConsumedShortControlTabDispatchesExactlyOnce() {
        let fixture = MonitorFixture()

        XCTAssertNil(fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
        ))
        XCTAssertNil(fixture.monitor.handleKeyUpEvent(
            fixture.event(.keyUp, timestamp: 10.249),
            context: fixture.context,
            emit: fixture.emit,
        ))

        XCTAssertEqual(fixture.commands, [.immediateMostRecentlyUsed])
    }

    /// CTM-004-short_hold_arbitration: 250ms and 251ms emit one overlay command.
    func testControlTabThresholdAndLaterReleaseEmitOverlayOnceWithoutImmediate() {
        for elapsed in [0.250, 0.251] {
            let fixture = MonitorFixture()
            _ = fixture.monitor.handleKeyDownEvent(
                fixture.event(.keyDown, timestamp: 10),
                context: fixture.context,
                firstResponder: nil,
                emit: fixture.emit,
            )
            fixture.fireScheduledHold()
            _ = fixture.monitor.handleKeyUpEvent(
                fixture.event(.keyUp, timestamp: 10 + elapsed),
                context: fixture.context,
                emit: fixture.emit,
            )

            XCTAssertEqual(fixture.commands, [.presentSwitcher], "elapsed=\(elapsed)")
        }
    }

    /// CTM-004-short_hold_arbitration: pending repeats and stale callbacks are ignored.
    func testPendingRepeatAndStaleHoldCallbackCannotDuplicate() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
        )
        _ = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10.01, repeat: true),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
        )
        fixture.fireScheduledHold()
        fixture.fireScheduledHold()

        XCTAssertEqual(fixture.commands, [.presentSwitcher])
    }

    /// CTM-004-short_hold_arbitration: release invalidates the scheduled generation.
    func testReleasedPendingGestureRejectsLateSchedulerAndReplacementToken() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
        )
        _ = fixture.monitor.handleKeyUpEvent(
            fixture.event(.keyUp, timestamp: 10.1),
            context: fixture.context,
            emit: fixture.emit,
        )
        let gestureA = fixture.scheduledCallbacks[0]
        _ = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 11),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
        )
        gestureA()
        XCTAssertEqual(fixture.commands, [.immediateMostRecentlyUsed])

        fixture.scheduledCallbacks[1]()

        XCTAssertEqual(fixture.commands, [.immediateMostRecentlyUsed, .presentSwitcher])
    }

    /// CTM-004-short_hold_arbitration: stale short release cannot switch a different focused window.
    /// Pending Control+Tab는 시작 창과 현재 창이 달라지면 MRU를 실행하지 않는지 검증한다.
    /// - 검증 내용: owner window mismatch short release
    /// - 사전 조건: 창 A에서 pending gesture가 시작된 뒤 창 B가 focused window가 된다.
    /// - 기대 결과: 명령 없이 gesture가 취소되고 창 B의 MRU는 변경되지 않는다.
    func testShortReleaseCancelsWhenFocusedWindowChanges() {
        let fixture = MonitorFixture()
        let ownerWindowID = UUID()
        let nextWindowID = UUID()
        let ownerContext = AppKeyboardShortcutMonitor.ContentTabShortcutContext(
            hasFocusedWindow: true,
            isComposerPresented: false,
            focusedWindowID: ownerWindowID,
        )
        let nextWindowContext = AppKeyboardShortcutMonitor.ContentTabShortcutContext(
            hasFocusedWindow: true,
            isComposerPresented: false,
            focusedWindowID: nextWindowID,
        )

        _ = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10),
            context: ownerContext,
            firstResponder: nil,
            emit: fixture.emit,
        )
        _ = fixture.monitor.handleKeyUpEvent(
            fixture.event(.keyUp, timestamp: 10.1),
            context: nextWindowContext,
            emit: fixture.emit,
        )

        XCTAssertTrue(fixture.commands.isEmpty)
    }

    /// CTM-004-short_hold_arbitration: stale short release cannot activate an automatic menu switcher.
    /// Pending Control+Tab가 메뉴 소유 전환기 표시와 충돌할 때 MRU를 실행하지 않는지 검증한다.
    /// - 검증 내용: automatic presentation short release
    /// - 사전 조건: pending gesture 중 automatic source switcher가 표시된다.
    /// - 기대 결과: 명령 없이 gesture가 취소되고 메뉴 전환기가 유지된다.
    func testShortReleaseCancelsWhenAutomaticPresentationAppears() {
        let fixture = MonitorFixture()
        let ownerWindowID = UUID()
        let ownerContext = AppKeyboardShortcutMonitor.ContentTabShortcutContext(
            hasFocusedWindow: true,
            isComposerPresented: false,
            focusedWindowID: ownerWindowID,
        )
        let automaticContext = AppKeyboardShortcutMonitor.ContentTabShortcutContext(
            hasFocusedWindow: true,
            isComposerPresented: false,
            isContentTabSwitcherPresented: true,
            focusedWindowID: ownerWindowID,
            contentTabSwitcherSource: .automatic,
        )

        _ = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10),
            context: ownerContext,
            firstResponder: nil,
            emit: fixture.emit,
        )
        _ = fixture.monitor.handleKeyUpEvent(
            fixture.event(.keyUp, timestamp: 10.1),
            context: automaticContext,
            emit: fixture.emit,
        )

        XCTAssertTrue(fixture.commands.isEmpty)
    }

    /// CTM-004-short_hold_arbitration: short release revalidates the latest text responder.
    /// Pending Control+Tab 중 텍스트 입력으로 포커스가 이동하면 MRU를 실행하지 않는지 검증한다.
    /// - 검증 내용: latest NSTextField responder short release
    /// - 사전 조건: FileManager에서 pending gesture를 시작한 뒤 텍스트 필드가 first responder가 된다.
    /// - 기대 결과: 명령 없이 pending gesture가 취소된다.
    func testShortReleaseCancelsWhenTextInputBecomesFirstResponder() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
        )

        _ = fixture.monitor.handleKeyUpEvent(
            fixture.event(.keyUp, timestamp: 10.1),
            context: fixture.context,
            firstResponder: NSTextField(),
            emit: fixture.emit,
        )
        fixture.fireScheduledHold()

        XCTAssertTrue(fixture.commands.isEmpty)
    }

    /// CTM-004-short_hold_arbitration: scheduled hold revalidates the latest text responder.
    /// Pending Control+Tab 중 텍스트 입력으로 포커스가 이동하면 switcher를 표시하지 않는지 검증한다.
    /// - 검증 내용: latest NSTextView responder scheduled hold
    /// - 사전 조건: FileManager에서 pending gesture를 시작한 뒤 텍스트 뷰가 first responder가 된다.
    /// - 기대 결과: 명령 없이 pending gesture가 취소된다.
    func testHoldCancelsWhenTextInputBecomesFirstResponder() {
        let fixture = MonitorFixture()
        var latestFirstResponder: NSResponder?
        _ = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
            latestFirstResponder: { latestFirstResponder },
        )

        latestFirstResponder = NSTextView()
        fixture.fireScheduledHold()

        XCTAssertTrue(fixture.commands.isEmpty)
    }

    /// CTM-004-short_hold_arbitration: overlay repeats navigate and Control release dismisses.
    func testOverlayTabRepeatsEmitNavigationAndControlReleaseDismisses() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
        )
        fixture.fireScheduledHold()
        _ = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10.3, shift: true),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
        )
        _ = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10.31, repeat: true),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
        )
        _ = fixture.monitor.handleFlagsChangedEvent(
            fixture.event(.flagsChanged, timestamp: 10.32, modifiers: []),
            context: fixture.context,
            emit: fixture.emit,
        )

        XCTAssertEqual(fixture.commands, [.presentSwitcher, .movePrevious, .movePrevious, .dismissSwitcher])
    }

    func testExternalDismissalResynchronizesHeldControlTabBeforeRetriggering() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
        )
        fixture.fireScheduledHold()

        let passedThroughExternalDismissal = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10.3),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
        )

        XCTAssertNil(passedThroughExternalDismissal)
        XCTAssertEqual(fixture.commands, [.presentSwitcher])

        fixture.fireScheduledHold()

        XCTAssertEqual(fixture.commands, [.presentSwitcher, .presentSwitcher])
    }

    /// CTM-004-short_hold_arbitration: resign-active and stop cancel pending input.
    func testResignAndStopCancelPendingGesture() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
        )
        fixture.monitor.applicationDidResignActive()
        fixture.fireScheduledHold()
        XCTAssertTrue(fixture.commands.isEmpty)

        _ = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 11),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
        )
        fixture.monitor.stop()
        fixture.fireScheduledHold()
        XCTAssertTrue(fixture.commands.isEmpty)

        let resignOverlayFixture = MonitorFixture()
        _ = resignOverlayFixture.monitor.handleKeyDownEvent(
            resignOverlayFixture.event(.keyDown, timestamp: 20),
            context: resignOverlayFixture.context,
            firstResponder: nil,
            emit: resignOverlayFixture.emit,
        )
        resignOverlayFixture.fireScheduledHold()
        resignOverlayFixture.monitor.applicationDidResignActive()
        resignOverlayFixture.fireScheduledHold()
        XCTAssertEqual(resignOverlayFixture.commands, [.presentSwitcher, .dismissSwitcher])

        let stopOverlayFixture = MonitorFixture()
        _ = stopOverlayFixture.monitor.handleKeyDownEvent(
            stopOverlayFixture.event(.keyDown, timestamp: 30),
            context: stopOverlayFixture.context,
            firstResponder: nil,
            emit: stopOverlayFixture.emit,
        )
        stopOverlayFixture.fireScheduledHold()
        stopOverlayFixture.monitor.stop()
        stopOverlayFixture.fireScheduledHold()
        XCTAssertEqual(stopOverlayFixture.commands, [.presentSwitcher, .dismissSwitcher])
    }

    /// CTM-004-short_hold_arbitration: invalid contexts and text editing pass through.
    func testInvalidContextAndTextEditingPassThrough() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.control], timestamp: 10,
            windowNumber: 0, context: nil, characters: "\t", charactersIgnoringModifiers: "\t",
            isARepeat: false, keyCode: UInt16(kVK_Tab),
        ))
        let fixture = MonitorFixture()

        XCTAssertIdentical(
            fixture.monitor.handleKeyDownEvent(event, context: .unavailable, firstResponder: nil, emit: fixture.emit),
            event,
        )
        XCTAssertIdentical(
            fixture.monitor
                .handleKeyDownEvent(event, context: fixture.context, firstResponder: NSTextView(), emit: fixture.emit),
            event,
        )
        XCTAssertTrue(fixture.commands.isEmpty)
    }

    /// CTM-004-short_hold_arbitration: invalid exact Control+Tab resets a pending gesture before pass-through.
    func testInvalidContextControlTabCancelsPendingGestureBeforeStaleHold() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
        )

        let passedThrough = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10.1),
            context: .unavailable,
            firstResponder: nil,
            emit: fixture.emit,
        )
        XCTAssertNotNil(passedThrough)

        fixture.fireScheduledHold()

        XCTAssertTrue(fixture.commands.isEmpty)

        let overlayFixture = MonitorFixture()
        _ = overlayFixture.monitor.handleKeyDownEvent(
            overlayFixture.event(.keyDown, timestamp: 20),
            context: overlayFixture.context,
            firstResponder: nil,
            emit: overlayFixture.emit,
        )
        overlayFixture.fireScheduledHold()

        let passedThroughOverlay = overlayFixture.monitor.handleKeyDownEvent(
            overlayFixture.event(.keyDown, timestamp: 20.1),
            context: .unavailable,
            firstResponder: nil,
            emit: overlayFixture.emit,
        )
        XCTAssertNotNil(passedThroughOverlay)
        overlayFixture.fireScheduledHold()
        XCTAssertEqual(overlayFixture.commands, [.presentSwitcher, .dismissSwitcher])
    }

    /// CTM-004-short_hold_arbitration: direct menu presentation is not owned by the raw monitor.
    func testDirectMenuSwitcherDoesNotDismissOnUnrelatedControlRelease() {
        let fixture = MonitorFixture()
        let directMenuContext = AppKeyboardShortcutMonitor.ContentTabShortcutContext(
            hasFocusedWindow: true,
            isComposerPresented: false,
            isContentTabSwitcherPresented: true,
        )

        let event = fixture.monitor.handleFlagsChangedEvent(
            fixture.event(.flagsChanged, timestamp: 10, modifiers: []),
            context: directMenuContext,
            emit: fixture.emit,
        )

        XCTAssertNotNil(event)
        XCTAssertTrue(fixture.commands.isEmpty)
    }

    /// CTM-004-short_hold_arbitration: malformed pending key-up resets and passes through.
    func testMalformedPendingKeyUpCancelsWithoutEmitting() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
        )

        let passedThrough = fixture.monitor.handleKeyUpEvent(
            fixture.event(.keyUp, timestamp: 10.1, modifiers: [.control, .option]),
            context: fixture.context,
            emit: fixture.emit,
        )
        XCTAssertNotNil(passedThrough)

        fixture.fireScheduledHold()

        XCTAssertTrue(fixture.commands.isEmpty)
    }

    func testMalformedOverlayKeyUpCancelsWithoutEmitting() {
        let fixture = MonitorFixture()
        _ = fixture.monitor.handleKeyDownEvent(
            fixture.event(.keyDown, timestamp: 10),
            context: fixture.context,
            firstResponder: nil,
            emit: fixture.emit,
        )
        fixture.fireScheduledHold()

        let passedThrough = fixture.monitor.handleKeyUpEvent(
            fixture.event(.keyUp, timestamp: 10.3, modifiers: [.control, .command]),
            context: fixture.context,
            emit: fixture.emit,
        )
        XCTAssertNotNil(passedThrough)
        XCTAssertEqual(fixture.commands, [.presentSwitcher, .dismissSwitcher])

        fixture.monitor.handleFlagsChangedEvent(
            fixture.event(.flagsChanged, timestamp: 10.4, modifiers: []),
            context: fixture.context,
            emit: fixture.emit,
        )
        XCTAssertEqual(fixture.commands, [.presentSwitcher, .dismissSwitcher])
    }

    /// CTM-004-short_hold_arbitration: Command and Option combinations pass through.
    func testCommandAndOptionTabPassThrough() throws {
        let fixture = MonitorFixture()
        for modifiers: NSEvent.ModifierFlags in [
            [.command, .control],
            [.option, .control],
            [.control, .shift, .option],
        ] {
            let event = try fixture.event(.keyDown, timestamp: 10, modifiers: modifiers)
            XCTAssertIdentical(
                fixture.monitor
                    .handleKeyDownEvent(event, context: fixture.context, firstResponder: nil, emit: fixture.emit),
                event,
            )
        }
        XCTAssertTrue(fixture.commands.isEmpty)

        let pendingFixture = MonitorFixture()
        _ = pendingFixture.monitor.handleKeyDownEvent(
            pendingFixture.event(.keyDown, timestamp: 20),
            context: pendingFixture.context,
            firstResponder: nil,
            emit: pendingFixture.emit,
        )
        XCTAssertNil(pendingFixture.monitor.handleFlagsChangedEvent(
            pendingFixture.event(.flagsChanged, timestamp: 20.1, modifiers: [.control, .option]),
            context: pendingFixture.context,
            emit: pendingFixture.emit,
        ))
        pendingFixture.fireScheduledHold()
        XCTAssertTrue(pendingFixture.commands.isEmpty)

        let overlayFixture = MonitorFixture()
        _ = overlayFixture.monitor.handleKeyDownEvent(
            overlayFixture.event(.keyDown, timestamp: 30),
            context: overlayFixture.context,
            firstResponder: nil,
            emit: overlayFixture.emit,
        )
        overlayFixture.fireScheduledHold()
        XCTAssertNil(overlayFixture.monitor.handleFlagsChangedEvent(
            overlayFixture.event(.flagsChanged, timestamp: 30.1, modifiers: [.control, .command]),
            context: overlayFixture.context,
            emit: overlayFixture.emit,
        ))
        overlayFixture.fireScheduledHold()
        XCTAssertEqual(overlayFixture.commands, [.presentSwitcher, .dismissSwitcher])
    }

    @MainActor
    private final class MonitorFixture {
        let context = AppKeyboardShortcutMonitor.ContentTabShortcutContext(
            hasFocusedWindow: true,
            isComposerPresented: false,
            isContentTabSwitcherPresented: false,
        )
        var scheduledCallbacks: [() -> Void] = []
        var commands: [AppKeyboardShortcutMonitor.ControlTabGestureCommand] = []
        lazy var monitor = AppKeyboardShortcutMonitor(holdScheduler: .init { _, callback in
            self.scheduledCallbacks.append(callback)
        })

        func emit(_ command: AppKeyboardShortcutMonitor.ControlTabGestureCommand) {
            commands.append(command)
        }

        func fireScheduledHold() {
            scheduledCallbacks.last?()
        }

        func event(
            _ type: NSEvent.EventType,
            timestamp: TimeInterval,
            shift: Bool = false,
            repeat: Bool = false,
            modifiers: NSEvent.ModifierFlags? = nil,
        ) -> NSEvent {
            let flags = modifiers ?? [.control, shift ? .shift : []]
            return NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: flags, timestamp: timestamp,
                windowNumber: 0, context: nil, characters: "\t", charactersIgnoringModifiers: "\t",
                isARepeat: `repeat`, keyCode: UInt16(kVK_Tab),
            )!
        }
    }
}
