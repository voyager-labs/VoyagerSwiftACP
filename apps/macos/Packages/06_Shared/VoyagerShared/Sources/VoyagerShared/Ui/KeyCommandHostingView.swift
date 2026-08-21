import AppKit
import SwiftUI

public class KeyCommandHostingView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?
    var onTextInput: ((String) -> Void)?

    // MARK: - NSTextInputClient 상태 저장소

    /// 조합 중인 marked text. 커밋(`insertText`) 시 해제된다.
    private var markedText: String = ""
    /// marked text 내 현재 선택 범위 (marked 문자열 UTF-16 기준으로 clamp된 값).
    private var markedSelectedRange: NSRange = .init(location: 0, length: 0)

    override public func keyDown(with event: NSEvent) {
        // Command/Control 조합은 항상 앱 단축키 경로로 보낸다 (Cmd+C, Cmd+Option+Delete 등). 조합 중에도 유지 (AC2/AC4).
        // Option 단독은 데드 키/printable 텍스트 입력일 수 있으므로 아래 문자 분류를 거치게 한다.
        if event.modifierFlags.isDisjoint(with: [.command, .control]) == false {
            onKeyDown?(event)
            return
        }
        // 조합 중에는 IME가 후보/조합 제어 키(Space, Return, Escape, 방향키, 제어/함수/공백)를 소유한다.
        // 입력 시스템에 먼저 전달해 소비하도록 한다 (AC1/AC3).
        if hasMarkedText() {
            interpretKeyEvents([event])
            return
        }
        // 조합 없음: printable 문자는 입력 시스템, 특수 키는 keyCommand 경로.
        if shouldRouteToKeyDown(event) {
            onKeyDown?(event)
            return
        }
        interpretKeyEvents([event])
    }

    /// `keyDown`을 `onKeyDown`으로 보낼지 판정한다.
    private func shouldRouteToKeyDown(_ event: NSEvent) -> Bool {
        // Command/Control 조합은 항상 앱 단축키 경로로 보낸다 (Cmd+C 등).
        // Option 단독은 아래 문자 분류(빈/제어/함수/공백/printable)로 판정한다.
        if event.modifierFlags.isDisjoint(with: [.command, .control]) == false {
            return true
        }
        guard let characters = event.characters else { return true }
        // 데드 키 초기 keyDown은 marked text가 생기기 전이라 characters가 빈 문자열이다.
        // 무수정 빈 문자는 텍스트 입력(IME 조합 시작)이므로 onKeyDown이 아닌 interpretKeyEvents로 보낸다.
        // arrows/Return/Escape/Space는 모두 비어 있지 않은 문자를 가지므로 아래 스칼라 검사에서 여전히 onKeyDown으로 유지된다.
        if characters.isEmpty {
            return false
        }
        guard let firstScalar = characters.unicodeScalars.first else { return false }

        // C0/C1 제어, 0x7F, 함수 키 영역(0xF700...0xF8FF), 공백은 입력 후보가 아니다.
        if firstScalar.value < 0x20
            || (0x7F ... 0x9F).contains(firstScalar.value)
            || (0xF700 ... 0xF8FF).contains(firstScalar.value)
        {
            return true
        }
        if Character(firstScalar).isWhitespace {
            return true
        }
        return false
    }

    override public func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override public var acceptsFirstResponder: Bool {
        true
    }
}

// MARK: - NSTextInputClient

extension KeyCommandHostingView: @MainActor NSTextInputClient {
    public func insertText(_ object: Any, replacementRange _: NSRange) {
        let text = textValue(from: object)
        // 어떤 경우든 marked state를 먼저 해제한다 (composition 종료).
        clearMarkedState()
        guard let text else { return }
        // 정확히 한 유효 그래핌 커밋만 `onTextInput`으로 전달한다.
        if CommittedTypeScrollInput.character(from: text) != nil {
            onTextInput?(text)
        }
    }

    public func setMarkedText(_ object: Any, selectedRange: NSRange, replacementRange _: NSRange) {
        let text = textValue(from: object)
        // 빈 문자열이면 composition 종료.
        guard let text, !text.isEmpty else {
            clearMarkedState()
            return
        }
        markedText = text
        // selectedRange를 marked 문자열 UTF-16 길이로 clamp.
        let utf16Length = (markedText as NSString).length
        markedSelectedRange = NSRange(
            location: min(selectedRange.location, utf16Length),
            length: min(selectedRange.length, max(0, utf16Length - min(selectedRange.location, utf16Length))),
        )
    }

    public func unmarkText() {
        clearMarkedState()
    }

    public func selectedRange() -> NSRange {
        guard !markedText.isEmpty else { return NSRange(location: 0, length: 0) }
        return markedSelectedRange
    }

    public func markedRange() -> NSRange {
        guard !markedText.isEmpty else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: 0, length: (markedText as NSString).length)
    }

    public func hasMarkedText() -> Bool {
        !markedText.isEmpty
    }

    public func attributedSubstring(
        forProposedRange _: NSRange,
        actualRange _: NSRangePointer?,
    ) -> NSAttributedString? {
        // 백킹 텍스트 스토리지가 없으므로 nil.
        nil
    }

    public func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    public func firstRect(forCharacterRange _: NSRange, actualRange _: NSRangePointer?) -> NSRect {
        // 후보 창 위치 근사: view bounds를 window 좌표로 변환. window가 없으면 zero.
        guard let window else { return .zero }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    public func characterIndex(for _: NSPoint) -> Int {
        NSNotFound
    }

    public func doCommandBy(_: Selector) {
        // 미바인딩 명령 흡수.
    }

    // MARK: - 내부 헬퍼

    /// marked 상태를 해제한다.
    private func clearMarkedState() {
        markedText = ""
        markedSelectedRange = .init(location: 0, length: 0)
    }

    /// `String`/`NSAttributedString`에서 문자열 값을 추출한다. 그 외 타입은 nil.
    private func textValue(from object: Any) -> String? {
        switch object {
        case let string as String:
            string
        case let attributed as NSAttributedString:
            attributed.string
        default:
            nil
        }
    }
}

public struct KeyCommandView: NSViewRepresentable {
    public var onViewCreated: ((KeyCommandHostingView) -> Void)?
    public var onKeyDown: (NSEvent) -> Void
    public var onTextInput: ((String) -> Void)?

    public init(
        onViewCreated: ((KeyCommandHostingView) -> Void)? = nil,
        onKeyDown: @escaping (NSEvent) -> Void,
        onTextInput: ((String) -> Void)? = nil,
    ) {
        self.onViewCreated = onViewCreated
        self.onKeyDown = onKeyDown
        self.onTextInput = onTextInput
    }

    public func makeNSView(context _: Context) -> KeyCommandHostingView {
        let view = KeyCommandHostingView()
        view.onKeyDown = onKeyDown
        view.onTextInput = onTextInput
        onViewCreated?(view)
        return view
    }

    public func updateNSView(_ nsView: KeyCommandHostingView, context _: Context) {
        nsView.onKeyDown = onKeyDown
        nsView.onTextInput = onTextInput
    }
}
