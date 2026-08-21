import AppKit
@testable import VoyagerShared
import XCTest

/// `KeyCommandHostingView`의 `NSTextInputClient` 상태 머신과 `keyDown` 라우팅 계약을 고정한다.
/// - client 계약: `setMarkedText`는 marked state만 갱신, `insertText`만 커밋 후 `onTextInput`을 호출.
/// - 라우팅: printable 무수정 문자만 `interpretKeyEvents`로, 그 외(space/함수키/단축키)는 `onKeyDown`으로.
@MainActor
final class EVM002KeyCommandHostingViewTextInputTests: XCTestCase {
    /// (i) 실제 클래스 client 계약 — marked text 조합 → 커밋 흐름.
    func testMarkedTextCompositionThenCommitInvokesOnTextInputOnce() {
        let view = KeyCommandHostingView()
        var committed: [String] = []
        view.onTextInput = { committed.append($0) }

        view.setMarkedText(
            "ㄱ",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )
        XCTAssertTrue(view.hasMarkedText())
        XCTAssertEqual(view.markedRange(), NSRange(location: 0, length: 1))
        XCTAssertEqual(committed.count, 0)

        view.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )
        XCTAssertTrue(view.hasMarkedText())

        view.insertText("가", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(view.markedRange().location, NSNotFound)
        XCTAssertEqual(committed, ["가"])
    }

    /// (i/ii) `unmarkText()`는 marked state를 해제하고 callback을 호출하지 않는다.
    func testUnmarkTextClearsMarkedStateWithoutCallback() {
        let view = KeyCommandHostingView()
        var committed: [String] = []
        view.onTextInput = { committed.append($0) }

        view.setMarkedText(
            "ㄱ",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )
        XCTAssertTrue(view.hasMarkedText())

        view.unmarkText()
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(view.markedRange().location, NSNotFound)
        XCTAssertEqual(committed.count, 0)
    }

    /// (ii) `setMarkedText`는 빈 문자열이면 composition을 종료한다.
    func testSetMarkedTextEmptyStringEndsComposition() {
        let view = KeyCommandHostingView()
        view.setMarkedText(
            "ㄱ",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )
        XCTAssertTrue(view.hasMarkedText())

        view.setMarkedText(
            "",
            selectedRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )
        XCTAssertFalse(view.hasMarkedText())
    }

    /// (iii) `NSAttributedString` 커밋도 정확히 1회 callback을 호출한다.
    func testAttributedStringInsertTextInvokesCallbackOnce() {
        let view = KeyCommandHostingView()
        var committed: [String] = []
        view.onTextInput = { committed.append($0) }

        view.insertText(NSAttributedString(string: "가"), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(committed, ["가"])
    }

    /// (iv) no-op 커밋 변형은 callback이 없고 marked state를 해제한다.
    func testNoopInsertTextVariantsDoNotInvokeCallback() {
        let view = KeyCommandHostingView()
        var committed: [String] = []
        view.onTextInput = { committed.append($0) }

        // marked 상태를 먼저 만들어, no-op 커밋이 이를 해제하는지 확인.
        view.setMarkedText(
            "ㄱ",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        view.insertText("", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(committed.count, 0)
        XCTAssertFalse(view.hasMarkedText())

        view.setMarkedText(
            "ㄱ",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )
        view.insertText("ab", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(committed.count, 0)
        XCTAssertFalse(view.hasMarkedText())

        view.setMarkedText(
            "ㄱ",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )
        view.insertText("가나", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(committed.count, 0)
        XCTAssertFalse(view.hasMarkedText())

        view.setMarkedText(
            "ㄱ",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )
        view.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(committed.count, 0)
        XCTAssertFalse(view.hasMarkedText())
    }

    /// (v) `setMarkedText`는 어떤 경우에도 `onTextInput`을 호출하지 않는다.
    func testSetMarkedTextNeverTriggersOnTextInput() {
        let view = KeyCommandHostingView()
        var committed: [String] = []
        view.onTextInput = { committed.append($0) }

        view.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )
        XCTAssertEqual(committed.count, 0)

        view.setMarkedText(
            NSAttributedString(string: "나"),
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )
        XCTAssertEqual(committed.count, 0)
    }

    /// markedRange는 marked text 전체를, 없으면 NSNotFound를 반환한다.
    func testMarkedRangeAndSelectedRangeProtocolConsistency() {
        let view = KeyCommandHostingView()
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(view.markedRange().location, NSNotFound)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 0))

        view.setMarkedText(
            "가나",
            selectedRange: NSRange(location: 0, length: 2),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )
        XCTAssertTrue(view.hasMarkedText())
        XCTAssertEqual(view.markedRange(), NSRange(location: 0, length: 2))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 2))
    }

    /// setMarkedText의 selectedRange는 marked 문자열 UTF-16 길이로 clamp된다.
    func testSetMarkedTextClampsSelectedRangeToMarkedLength() {
        let view = KeyCommandHostingView()
        view.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 99),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 1))
    }

    /// (vi) spy 라우팅 — printable 무수정 문자는 interpretKeyEvents로만 흘러간다.
    func testPrintableKeyDownRoutesThroughInterpretKeyEvents() {
        let spy = InputSystemSpyHostingView()
        var keyDowns: [NSEvent] = []
        var committed: [String] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.onTextInput = { committed.append($0) }

        spy.keyDown(with: makeKeyDown(characters: "a"))

        XCTAssertEqual(spy.interpretedEvents.count, 1)
        XCTAssertEqual(keyDowns.count, 0)
        XCTAssertEqual(committed, ["a"])
    }

    /// (vi) space는 Quick Look 보존을 위해 onKeyDown으로만 흘러간다.
    func testSpaceKeyDownRoutesToOnKeyDown() {
        let spy = InputSystemSpyHostingView()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }

        spy.keyDown(with: makeKeyDown(characters: " "))

        XCTAssertEqual(spy.interpretedEvents.count, 0)
        XCTAssertEqual(keyDowns.count, 1)
    }

    /// (vi) 함수 키(방향키) 문자는 onKeyDown으로만 흘러간다.
    func testFunctionKeyKeyDownRoutesToOnKeyDown() {
        let spy = InputSystemSpyHostingView()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }

        spy.keyDown(with: makeKeyDown(characters: "\u{F702}"))

        XCTAssertEqual(spy.interpretedEvents.count, 0)
        XCTAssertEqual(keyDowns.count, 1)
    }

    /// (vi) command 조합 단축키는 onKeyDown으로만 흘러간다.
    func testCommandKeyDownRoutesToOnKeyDown() {
        let spy = InputSystemSpyHostingView()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }

        spy.keyDown(with: makeKeyDown(characters: "c", modifierFlags: [.command]))

        XCTAssertEqual(spy.interpretedEvents.count, 0)
        XCTAssertEqual(keyDowns.count, 1)
    }

    /// (vii) 실제 `KeyCommandHostingView`에서 `onTextInput` 연결과 `insertText` 커밋이 callback을 발생시킨다.
    func testOnTextInputWiringOnRealHostingView() {
        let view = KeyCommandHostingView()
        var committed: [String] = []
        view.onTextInput = { committed.append($0) }

        view.insertText("가", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(committed, ["가"])
    }

    // MARK: - IME 조합 중 우선순위 (VOY-661 P1)

    /// 조합 중 Return(0x0D)은 입력 시스템에 먼저 전달돼야 한다. (AC1/AC3)
    func testMarkedReturnOfferedToInputSystemNotOnKeyDown() {
        let spy = InputSystemSpyHostingView()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        spy.keyDown(with: makeKeyDown(characters: "\r"))

        XCTAssertEqual(spy.interpretedEvents.count, 1)
        XCTAssertEqual(keyDowns.count, 0)
    }

    /// 조합 중 Space는 입력 시스템에 먼저 전달돼야 한다. (AC1/AC3)
    func testMarkedSpaceOfferedToInputSystemNotOnKeyDown() {
        let spy = InputSystemSpyHostingView()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        spy.keyDown(with: makeKeyDown(characters: " "))

        XCTAssertEqual(spy.interpretedEvents.count, 1)
        XCTAssertEqual(keyDowns.count, 0)
    }

    /// 조합 중 Escape(0x1B)는 입력 시스템에 먼저 전달돼야 한다. (AC1/AC3)
    func testMarkedEscapeOfferedToInputSystemNotOnKeyDown() {
        let spy = InputSystemSpyHostingView()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        spy.keyDown(with: makeKeyDown(characters: "\u{001B}"))

        XCTAssertEqual(spy.interpretedEvents.count, 1)
        XCTAssertEqual(keyDowns.count, 0)
    }

    /// 조합 중 방향키(함수 키 0xF700...0xF8FF)는 입력 시스템에 먼저 전달돼야 한다. (AC1/AC3)
    func testMarkedArrowOfferedToInputSystemNotOnKeyDown() {
        let spy = InputSystemSpyHostingView()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        spy.keyDown(with: makeKeyDown(characters: "\u{F702}"))

        XCTAssertEqual(spy.interpretedEvents.count, 1)
        XCTAssertEqual(keyDowns.count, 0)
    }

    /// 조합 중 command 단축키는 여전히 onKeyDown으로 (AC4). 조합 중에도 Cmd+C는 단축키.
    func testModifierComboDuringMarkedRoutesToOnKeyDown() {
        let spy = InputSystemSpyHostingView()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        spy.keyDown(with: makeKeyDown(characters: "c", modifierFlags: [.command]))

        XCTAssertEqual(spy.interpretedEvents.count, 0)
        XCTAssertEqual(keyDowns.count, 1)
    }

    /// 조합 없이 Space는 onKeyDown (비회귀: Quick Look 보존).
    func testNoMarkedSpaceRoutesToOnKeyDown() {
        let spy = InputSystemSpyHostingView()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }

        spy.keyDown(with: makeKeyDown(characters: " "))

        XCTAssertEqual(spy.interpretedEvents.count, 0)
        XCTAssertEqual(keyDowns.count, 1)
    }

    /// 조합 없이 printable은 입력 시스템으로 (비회귀: type-scroll 보존).
    func testNoMarkedPrintableRoutesThroughInterpretKeyEvents() {
        let spy = InputSystemSpyHostingView()
        var keyDowns: [NSEvent] = []
        var committed: [String] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.onTextInput = { committed.append($0) }

        spy.keyDown(with: makeKeyDown(characters: "a"))

        XCTAssertEqual(spy.interpretedEvents.count, 1)
        XCTAssertEqual(keyDowns.count, 0)
        XCTAssertEqual(committed, ["a"])
    }

    // MARK: - 데드 키 (문자 없음, 무수정) 라우팅 (VOY-661)

    /// 데드 키의 초기 keyDown은 marked text가 생기기 전이라 `characters == ""`다. 이는 앱 명령이 아니라
    /// 텍스트 입력 이벤트이므로 `interpretKeyEvents`로 보내 IME 조합을 시작해야 한다.
    func testDeadKeyEmptyCharacterRoutesThroughInterpretKeyEventsNotOnKeyDown() {
        let spy = InputSystemSpyHostingView()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }

        spy.keyDown(with: makeKeyDown(characters: ""))

        XCTAssertEqual(spy.interpretedEvents.count, 1)
        XCTAssertEqual(keyDowns.count, 0)
    }

    /// 데드 키의 빈 문자 이벤트가 `interpretKeyEvents`에 도달하면 IME가 조합(marked text)을 시작할 수 있다.
    /// 조합 시작을 시뮬레이션하는 스파이로 marked state 진입을 검증한다.
    func testDeadKeyEmptyCharacterStartsMarkedComposition() {
        let spy = DeadKeyInputSystemSpyHostingView()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }

        spy.keyDown(with: makeKeyDown(characters: ""))

        XCTAssertEqual(spy.interpretedEvents.count, 1)
        XCTAssertEqual(keyDowns.count, 0)
        XCTAssertTrue(spy.hasMarkedText(), "dead key must start IME composition via interpretKeyEvents")
    }

    // MARK: - Option 데드 키 / Option 생성 printable 라우팅 (VOY-661)

    /// Option+E 등 Option 데드 키의 초기 keyDown은 marked text가 생기기 전이라 `characters == ""`다.
    /// FileManagerContentKeyCommandHandler는 Option 단독 텍스트를 소비하지 않으므로 앱 명령이 아니라
    /// 텍스트 입력 이벤트로 분류해 `interpretKeyEvents`로 보내야 한다.
    func testOptionDeadKeyEmptyCharacterRoutesThroughInterpretKeyEventsNotOnKeyDown() {
        let spy = InputSystemSpyHostingView()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }

        spy.keyDown(with: makeKeyDown(characters: "", modifierFlags: [.option]))

        XCTAssertEqual(spy.interpretedEvents.count, 1)
        XCTAssertEqual(keyDowns.count, 0)
    }

    /// Option으로 생성된 printable 문자(예: US 레이아웃 Option+E → U+00B4 acute accent)도
    /// 앱 명령이 아니라 텍스트 입력이므로 `interpretKeyEvents`로 보내 커밋돼야 한다.
    func testOptionPrintableCharacterRoutesThroughInterpretKeyEventsNotOnKeyDown() {
        let spy = InputSystemSpyHostingView()
        var keyDowns: [NSEvent] = []
        var committed: [String] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.onTextInput = { committed.append($0) }

        spy.keyDown(with: makeKeyDown(characters: "\u{00B4}", modifierFlags: [.option]))

        XCTAssertEqual(spy.interpretedEvents.count, 1)
        XCTAssertEqual(keyDowns.count, 0)
        XCTAssertEqual(committed, ["\u{00B4}"])
    }
}

extension EVM002KeyCommandHostingViewTextInputTests {
    // MARK: - EVM-002-type_scroll_text_input

    /// EVM-002-type_scroll_text_input: Escape command가 진행 중인 IME 조합을 취소한다.
    /// 입력 시스템이 Escape를 `cancelOperation:`으로 전달하는 경로를 검증한다.
    /// - 검증 내용: marked text와 selected/marked range가 함께 초기화된다.
    /// - 사전 조건: 선택 범위가 있는 marked text가 설정되어 있다.
    /// - 기대 결과: 조합 상태만 해제되고 app/text callback은 호출되지 않는다.
    func testCancelOperationClearsMarkedStateAndRangesWithoutCallbacks() {
        let view = KeyCommandHostingView()
        var keyDowns: [NSEvent] = []
        var committed: [String] = []
        view.onKeyDown = { keyDowns.append($0) }
        view.onTextInput = { committed.append($0) }
        view.setMarkedText(
            "가나",
            selectedRange: NSRange(location: 1, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        view.doCommandBy(#selector(NSResponder.cancelOperation(_:)))

        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(view.markedRange(), NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertTrue(keyDowns.isEmpty)
        XCTAssertTrue(committed.isEmpty)
    }

    /// EVM-002-type_scroll_text_input: IME 취소 뒤 특수 키는 기존 앱 command 경로로 복귀한다.
    /// Escape로 조합을 닫은 다음 Quick Look, 실행, 탐색 키를 연속 입력하는 경로를 검증한다.
    /// - 검증 내용: Space/Return/네 방향키의 `keyDown` 라우팅 횟수와 입력 시스템 호출 횟수.
    /// - 사전 조건: marked text를 설정한 뒤 `cancelOperation:`을 호출했다.
    /// - 기대 결과: 모든 특수 키가 `onKeyDown`으로 한 번씩 전달되고 text callback은 없다.
    func testApplicationCommandsResumeAfterCancelOperation() {
        let spy = InputSystemSpyHostingView()
        var keyDowns: [NSEvent] = []
        var committed: [String] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.onTextInput = { committed.append($0) }
        spy.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )
        spy.doCommandBy(#selector(NSResponder.cancelOperation(_:)))

        for item in [" ", "\r", "\u{F700}", "\u{F701}", "\u{F702}", "\u{F703}"] {
            spy.keyDown(with: makeKeyDown(characters: item))
        }

        XCTAssertEqual(keyDowns.count, 6)
        XCTAssertTrue(spy.interpretedEvents.isEmpty)
        XCTAssertTrue(committed.isEmpty)
    }

    /// EVM-002-type_scroll_text_input: 표준 편집 selector는 앱 command로 중복 전달되지 않는다.
    /// 입력 시스템이 조합 중 newline/tab/movement/delete selector를 전달하는 경로를 검증한다.
    /// - 검증 내용: selector 처리 뒤 marked state와 callback 횟수.
    /// - 사전 조건: marked text가 활성화되어 있다.
    /// - 기대 결과: selector가 안전하게 소비되고 조합 상태와 callback이 변하지 않는다.
    func testTextInputCommandSelectorsPreserveCompositionWithoutCallbacks() {
        let view = KeyCommandHostingView()
        var keyDowns: [NSEvent] = []
        var committed: [String] = []
        view.onKeyDown = { keyDowns.append($0) }
        view.onTextInput = { committed.append($0) }
        view.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        [
            #selector(NSResponder.insertNewline(_:)),
            #selector(NSResponder.insertTab(_:)),
            #selector(NSResponder.moveUp(_:)),
            #selector(NSResponder.moveDown(_:)),
            #selector(NSResponder.moveLeft(_:)),
            #selector(NSResponder.moveRight(_:)),
            #selector(NSResponder.deleteBackward(_:)),
            #selector(NSResponder.deleteForward(_:)),
        ].forEach(view.doCommandBy)

        XCTAssertTrue(view.hasMarkedText())
        XCTAssertEqual(view.markedRange(), NSRange(location: 0, length: 1))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 1))
        XCTAssertTrue(keyDowns.isEmpty)
        XCTAssertTrue(committed.isEmpty)
    }

    /// EVM-002-type_scroll_text_input: 알 수 없는 selector는 조합 상태를 손상하지 않고 소비한다.
    /// AppKit 또는 입력기가 미지원 selector를 전달하는 안전 경계를 검증한다.
    /// - 검증 내용: marked state와 app/text callback 횟수.
    /// - 사전 조건: marked text가 활성화되어 있다.
    /// - 기대 결과: selector 전달 전후 상태가 동일하고 callback은 없다.
    func testUnknownCommandSelectorPreservesCompositionWithoutCallbacks() {
        let view = KeyCommandHostingView()
        var keyDowns: [NSEvent] = []
        var committed: [String] = []
        view.onKeyDown = { keyDowns.append($0) }
        view.onTextInput = { committed.append($0) }
        view.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        view.doCommandBy(NSSelectorFromString("unrelatedTextCommand:"))

        XCTAssertTrue(view.hasMarkedText())
        XCTAssertEqual(view.markedRange(), NSRange(location: 0, length: 1))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 1))
        XCTAssertTrue(keyDowns.isEmpty)
        XCTAssertTrue(committed.isEmpty)
    }

    /// EVM-002-type_scroll_text_input: Command/Control 조합은 marked text 중에도 앱 command 경로를 유지한다.
    /// Command+Option 조합을 포함한 기존 단축키 우선순위의 비회귀를 검증한다.
    /// - 검증 내용: modifier 조합별 `onKeyDown`과 입력 시스템 호출 횟수.
    /// - 사전 조건: marked text가 활성화되어 있다.
    /// - 기대 결과: Command, Control, Command+Option이 각각 앱 경로로 한 번 전달된다.
    func testCommandControlAndCommandOptionDuringMarkedRouteToOnKeyDown() {
        let spy = InputSystemSpyHostingView()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        [
            NSEvent.ModifierFlags.command,
            NSEvent.ModifierFlags.control,
            [.command, .option],
        ].forEach {
            spy.keyDown(with: makeKeyDown(characters: "c", modifierFlags: $0))
        }

        XCTAssertEqual(keyDowns.count, 3)
        XCTAssertTrue(spy.interpretedEvents.isEmpty)
        XCTAssertTrue(spy.hasMarkedText())
    }

    /// 스파이 뷰: `interpretKeyEvents`를 override해 입력 시스템을 시뮬레이션한다.
    private final class InputSystemSpyHostingView: KeyCommandHostingView {
        var interpretedEvents: [NSEvent] = []

        override func interpretKeyEvents(_ eventArray: [NSEvent]) {
            interpretedEvents.append(contentsOf: eventArray)
            for event in eventArray {
                insertText(event.characters ?? "", replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }
    }

    /// 데드 키 입력 시스템 스파이: 빈 문자 이벤트를 결합 악센트 조합(marked text) 시작으로 처리한다.
    private final class DeadKeyInputSystemSpyHostingView: KeyCommandHostingView {
        var interpretedEvents: [NSEvent] = []

        override func interpretKeyEvents(_ eventArray: [NSEvent]) {
            interpretedEvents.append(contentsOf: eventArray)
            for _ in eventArray {
                setMarkedText(
                    "\u{0301}",
                    selectedRange: NSRange(location: 0, length: 1),
                    replacementRange: NSRange(location: NSNotFound, length: 0),
                )
            }
        }
    }

    /// synthetic keyDown 이벤트를 만든다.
    private func makeKeyDown(characters: String, modifierFlags: NSEvent.ModifierFlags = []) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0,
        ) else {
            preconditionFailure("keyDown 이벤트 생성 실패")
        }
        return event
    }
}
