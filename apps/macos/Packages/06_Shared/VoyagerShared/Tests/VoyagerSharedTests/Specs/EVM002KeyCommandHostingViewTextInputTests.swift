import AppKit
@testable import VoyagerShared
import XCTest

/// `KeyCommandHostingView`의 `NSTextInputClient` 상태 머신과 `keyDown` 라우팅 계약을 고정한다.
/// - client 계약: `setMarkedText`는 marked state만 갱신, `insertText`/`unmarkText`가 커밋 후 `onTextInput`을 호출.
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
        let (spy, interpretedEvents) = makeInputSystemSpy()
        var keyDowns: [NSEvent] = []
        var committed: [String] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.onTextInput = { committed.append($0) }

        spy.keyDown(with: makeKeyDown(characters: "a"))

        XCTAssertEqual(interpretedEvents().count, 1)
        XCTAssertEqual(keyDowns.count, 0)
        XCTAssertEqual(committed, ["a"])
    }

    /// (vi) space는 Quick Look 보존을 위해 onKeyDown으로만 흘러간다.
    func testSpaceKeyDownRoutesToOnKeyDown() {
        let (spy, interpretedEvents) = makeInputSystemSpy()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }

        spy.keyDown(with: makeKeyDown(characters: " "))

        XCTAssertEqual(interpretedEvents().count, 0)
        XCTAssertEqual(keyDowns.count, 1)
    }

    /// (vi) 함수 키(방향키) 문자는 onKeyDown으로만 흘러간다.
    func testFunctionKeyKeyDownRoutesToOnKeyDown() {
        let (spy, interpretedEvents) = makeInputSystemSpy()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }

        spy.keyDown(with: makeKeyDown(characters: "\u{F702}"))

        XCTAssertEqual(interpretedEvents().count, 0)
        XCTAssertEqual(keyDowns.count, 1)
    }

    /// (vi) command 조합 단축키는 onKeyDown으로만 흘러간다.
    func testCommandKeyDownRoutesToOnKeyDown() {
        let (spy, interpretedEvents) = makeInputSystemSpy()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }

        spy.keyDown(with: makeKeyDown(characters: "c", modifierFlags: [.command]))

        XCTAssertEqual(interpretedEvents().count, 0)
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
        let (spy, interpretedEvents) = makeInputSystemSpy()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        spy.keyDown(with: makeKeyDown(characters: "\r"))

        XCTAssertEqual(interpretedEvents().count, 1)
        XCTAssertEqual(keyDowns.count, 0)
    }

    /// 조합 중 Space는 입력 시스템에 먼저 전달돼야 한다. (AC1/AC3)
    func testMarkedSpaceOfferedToInputSystemNotOnKeyDown() {
        let (spy, interpretedEvents) = makeInputSystemSpy()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        spy.keyDown(with: makeKeyDown(characters: " "))

        XCTAssertEqual(interpretedEvents().count, 1)
        XCTAssertEqual(keyDowns.count, 0)
    }

    /// 조합 중 Escape(0x1B)는 입력 시스템에 먼저 전달돼야 한다. (AC1/AC3)
    func testMarkedEscapeOfferedToInputSystemNotOnKeyDown() {
        let (spy, interpretedEvents) = makeInputSystemSpy()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        spy.keyDown(with: makeKeyDown(characters: "\u{001B}"))

        XCTAssertEqual(interpretedEvents().count, 1)
        XCTAssertEqual(keyDowns.count, 0)
    }

    /// 조합 중 방향키(함수 키 0xF700...0xF8FF)는 입력 시스템에 먼저 전달돼야 한다. (AC1/AC3)
    func testMarkedArrowOfferedToInputSystemNotOnKeyDown() {
        let (spy, interpretedEvents) = makeInputSystemSpy()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        spy.keyDown(with: makeKeyDown(characters: "\u{F702}"))

        XCTAssertEqual(interpretedEvents().count, 1)
        XCTAssertEqual(keyDowns.count, 0)
    }

    /// 조합 중 command 단축키는 여전히 onKeyDown으로 (AC4). 조합 중에도 Cmd+C는 단축키.
    func testModifierComboDuringMarkedRoutesToOnKeyDown() {
        let (spy, interpretedEvents) = makeInputSystemSpy()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        spy.keyDown(with: makeKeyDown(characters: "c", modifierFlags: [.command]))

        XCTAssertEqual(interpretedEvents().count, 0)
        XCTAssertEqual(keyDowns.count, 1)
    }

    /// 조합 없이 Space는 onKeyDown (비회귀: Quick Look 보존).
    func testNoMarkedSpaceRoutesToOnKeyDown() {
        let (spy, interpretedEvents) = makeInputSystemSpy()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }

        spy.keyDown(with: makeKeyDown(characters: " "))

        XCTAssertEqual(interpretedEvents().count, 0)
        XCTAssertEqual(keyDowns.count, 1)
    }

    /// 조합 없이 printable은 입력 시스템으로 (비회귀: type-scroll 보존).
    func testNoMarkedPrintableRoutesThroughInterpretKeyEvents() {
        let (spy, interpretedEvents) = makeInputSystemSpy()
        var keyDowns: [NSEvent] = []
        var committed: [String] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.onTextInput = { committed.append($0) }

        spy.keyDown(with: makeKeyDown(characters: "a"))

        XCTAssertEqual(interpretedEvents().count, 1)
        XCTAssertEqual(keyDowns.count, 0)
        XCTAssertEqual(committed, ["a"])
    }

    // MARK: - 데드 키 (문자 없음, 무수정) 라우팅 (VOY-661)

    /// 데드 키의 초기 keyDown은 marked text가 생기기 전이라 `characters == ""`다. 이는 앱 명령이 아니라
    /// 텍스트 입력 이벤트이므로 `interpretKeyEvents`로 보내 IME 조합을 시작해야 한다.
    func testDeadKeyEmptyCharacterRoutesThroughInterpretKeyEventsNotOnKeyDown() {
        let (spy, interpretedEvents) = makeInputSystemSpy()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }

        spy.keyDown(with: makeKeyDown(characters: ""))

        XCTAssertEqual(interpretedEvents().count, 1)
        XCTAssertEqual(keyDowns.count, 0)
    }

    /// 데드 키의 빈 문자 이벤트가 `interpretKeyEvents`에 도달하면 IME가 조합(marked text)을 시작할 수 있다.
    /// 조합 시작을 시뮬레이션하는 스파이로 marked state 진입을 검증한다.
    func testDeadKeyEmptyCharacterStartsMarkedComposition() {
        let (spy, interpretedEvents) = makeInputSystemSpy { view, _ in
            view.setMarkedText(
                "\u{0301}",
                selectedRange: NSRange(location: 0, length: 1),
                replacementRange: NSRange(location: NSNotFound, length: 0),
            )
        }
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }

        spy.keyDown(with: makeKeyDown(characters: ""))

        XCTAssertEqual(interpretedEvents().count, 1)
        XCTAssertEqual(keyDowns.count, 0)
        XCTAssertTrue(spy.hasMarkedText(), "dead key must start IME composition via interpretKeyEvents")
    }

    // MARK: - Option 데드 키 / Option 생성 printable 라우팅 (VOY-661)

    /// Option+E 등 Option 데드 키의 초기 keyDown은 marked text가 생기기 전이라 `characters == ""`다.
    /// FileManagerContentKeyCommandHandler는 Option 단독 텍스트를 소비하지 않으므로 앱 명령이 아니라
    /// 텍스트 입력 이벤트로 분류해 `interpretKeyEvents`로 보내야 한다.
    func testOptionDeadKeyEmptyCharacterRoutesThroughInterpretKeyEventsNotOnKeyDown() {
        let (spy, interpretedEvents) = makeInputSystemSpy()
        var keyDowns: [NSEvent] = []
        spy.onKeyDown = { keyDowns.append($0) }

        spy.keyDown(with: makeKeyDown(characters: "", modifierFlags: [.option]))

        XCTAssertEqual(interpretedEvents().count, 1)
        XCTAssertEqual(keyDowns.count, 0)
    }

    /// Option으로 생성된 printable 문자(예: US 레이아웃 Option+E → U+00B4 acute accent)도
    /// 앱 명령이 아니라 텍스트 입력이므로 `interpretKeyEvents`로 보내 커밋돼야 한다.
    func testOptionPrintableCharacterRoutesThroughInterpretKeyEventsNotOnKeyDown() {
        let (spy, interpretedEvents) = makeInputSystemSpy()
        var keyDowns: [NSEvent] = []
        var committed: [String] = []
        spy.onKeyDown = { keyDowns.append($0) }
        spy.onTextInput = { committed.append($0) }

        spy.keyDown(with: makeKeyDown(characters: "\u{00B4}", modifierFlags: [.option]))

        XCTAssertEqual(interpretedEvents().count, 1)
        XCTAssertEqual(keyDowns.count, 0)
        XCTAssertEqual(committed, ["\u{00B4}"])
    }
}

extension EVM002KeyCommandHostingViewTextInputTests {
    // MARK: - EVM-002-type_scroll_text_input

    /// EVM-002-type_scroll_text_input: `unmarkText`가 유효한 marked text를 한 번 커밋한다.
    /// 입력기가 `insertText` 대신 `unmarkText`로 현재 조합을 확정하는 경로를 검증한다.
    /// - 검증 내용: 검증된 문자열 callback 횟수와 marked/selected range 초기화.
    /// - 사전 조건: 선택 범위가 있는 유효한 단일 그래핌 marked text가 설정되어 있다.
    /// - 기대 결과: 문자열이 정확히 한 번 전달되고 조합 상태와 범위가 모두 해제된다.
    func testUnmarkTextCommitsValidMarkedTextOnceAndClearsRanges() {
        let view = KeyCommandHostingView()
        var committed: [String] = []
        view.onTextInput = { committed.append($0) }
        view.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        view.unmarkText()

        XCTAssertEqual(committed, ["가"])
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(view.markedRange(), NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 0))
    }

    /// EVM-002-type_scroll_text_input: attributed marked text도 plain string으로 한 번 커밋한다.
    /// 속성이 포함된 IME 조합 문자열의 실제 텍스트 값이 보존되는 경로를 검증한다.
    /// - 검증 내용: `NSAttributedString.string` 추출값과 callback 횟수.
    /// - 사전 조건: attributed 단일 그래핌 marked text가 설정되어 있다.
    /// - 기대 결과: plain string만 정확히 한 번 전달되고 marked state가 해제된다.
    func testUnmarkTextCommitsAttributedMarkedTextAsPlainStringOnce() {
        let view = KeyCommandHostingView()
        var committed: [String] = []
        view.onTextInput = { committed.append($0) }
        view.setMarkedText(
            NSAttributedString(string: "나", attributes: [.foregroundColor: NSColor.red]),
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        view.unmarkText()

        XCTAssertEqual(committed, ["나"])
        XCTAssertFalse(view.hasMarkedText())
    }

    /// EVM-002-type_scroll_text_input: 유효하지 않은 marked text는 커밋하지 않고 해제한다.
    /// 빈 값, 다중 그래핌, 공백, 제어 문자 조합의 안전한 종료 경로를 검증한다.
    /// - 검증 내용: `CommittedTypeScrollInput` 거부 입력의 callback과 marked state.
    /// - 사전 조건: 각 유효하지 않은 문자열을 marked text로 설정한다.
    /// - 기대 결과: callback 없이 조합 상태가 해제된다.
    func testUnmarkTextRejectsInvalidMarkedTextAndClearsState() {
        for text in ["", "가나", " ", "\u{001F}"] {
            let view = KeyCommandHostingView()
            var committed: [String] = []
            view.onTextInput = { committed.append($0) }
            view.setMarkedText(
                text,
                selectedRange: NSRange(location: 0, length: (text as NSString).length),
                replacementRange: NSRange(location: NSNotFound, length: 0),
            )

            view.unmarkText()

            XCTAssertTrue(committed.isEmpty, "unexpected commit for \(text.debugDescription)")
            XCTAssertFalse(view.hasMarkedText(), "marked state remained for \(text.debugDescription)")
            XCTAssertEqual(view.markedRange(), NSRange(location: NSNotFound, length: 0))
            XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 0))
        }
    }

    /// EVM-002-type_scroll_text_input: `insertText` 뒤의 `unmarkText`는 중복 커밋하지 않는다.
    /// 일부 입력기가 조합 확정 뒤 추가로 unmark를 보내는 경로를 검증한다.
    /// - 검증 내용: 두 protocol 호출 뒤 callback 누적 횟수.
    /// - 사전 조건: 유효한 marked text를 같은 문자열로 `insertText` 커밋한다.
    /// - 기대 결과: 후속 `unmarkText`는 no-op이고 문자열은 한 번만 전달된다.
    func testUnmarkTextAfterInsertTextDoesNotDoubleCommit() {
        let view = KeyCommandHostingView()
        var committed: [String] = []
        view.onTextInput = { committed.append($0) }
        view.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        view.insertText("가", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.unmarkText()

        XCTAssertEqual(committed, ["가"])
        XCTAssertFalse(view.hasMarkedText())
    }

    /// EVM-002-type_scroll_text_input: 반복 `unmarkText`는 첫 커밋 뒤 멱등이다.
    /// 입력기가 같은 조합 종료 신호를 중복 전달하는 경로를 검증한다.
    /// - 검증 내용: 반복 호출 뒤 callback 누적 횟수와 marked state.
    /// - 사전 조건: 유효한 marked text가 한 번 설정되어 있다.
    /// - 기대 결과: 첫 호출만 커밋하고 이후 호출은 callback 없는 no-op이다.
    func testRepeatedUnmarkTextIsIdempotent() {
        let view = KeyCommandHostingView()
        var committed: [String] = []
        view.onTextInput = { committed.append($0) }
        view.setMarkedText(
            "가",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )

        view.unmarkText()
        view.unmarkText()

        XCTAssertEqual(committed, ["가"])
        XCTAssertFalse(view.hasMarkedText())
    }

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
            "가",
            selectedRange: NSRange(location: 0, length: 1),
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
        let (spy, interpretedEvents) = makeInputSystemSpy()
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
        XCTAssertTrue(interpretedEvents().isEmpty)
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
        let (spy, interpretedEvents) = makeInputSystemSpy()
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
        XCTAssertTrue(interpretedEvents().isEmpty)
        XCTAssertTrue(spy.hasMarkedText())
    }

    private func makeInputSystemSpy(
        handleEvent: @escaping (KeyCommandHostingView, NSEvent) -> Void = { view, event in
            view.insertText(
                event.characters ?? "",
                replacementRange: NSRange(location: NSNotFound, length: 0),
            )
        },
    ) -> (view: KeyCommandHostingView, interpretedEvents: () -> [NSEvent]) {
        let view = KeyCommandHostingView()
        var interpretedEvents: [NSEvent] = []
        view.interpretKeyEventsHandler = { [weak view] events in
            interpretedEvents.append(contentsOf: events)
            guard let view else { return }
            for event in events {
                handleEvent(view, event)
            }
        }
        return (view, { interpretedEvents })
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
