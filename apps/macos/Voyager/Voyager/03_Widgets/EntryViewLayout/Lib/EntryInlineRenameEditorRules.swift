import AppKit
import Foundation

public enum EntryInlineRenameEditorRules {
    public enum CommandAction: Equatable {
        case commit
        case cancel
        case none
    }

    public static let maxLines = 3

    public static func applyWrappingStyle(to textField: NSTextField) {
        textField.usesSingleLineMode = false
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = maxLines
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
    }

    /// 입력 문자열에서 줄바꿈 문자 제거
    public static func sanitizeInput(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }

    /// 키보드 커맨드에 대한 액션 결정
    public static func commandAction(for commandSelector: Selector) -> CommandAction {
        if commandSelector == #selector(NSResponder.insertNewline(_:))
            || commandSelector == #selector(NSResponder.insertTab(_:))
        {
            return .commit
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            return .cancel
        }
        return .none
    }

    /// 리네임 시작 시 초기 선택 범위 계산
    /// - Parameters:
    ///   - displayName: 파일/폴더 표시 이름
    ///   - isFolder: 폴더 여부
    /// - Returns: 선택할 NSRange
    /// - Note: Finder 스타일 규칙
    ///   - `report.txt` → `report` 선택 (확장자 제외)
    ///   - `README` → 전체 선택 (확장자 없음)
    ///   - `.env` → 전체 선택 (dotfile은 extensionless 취급)
    ///   - `archive.tar.gz` → `archive.tar` 선택 (마지막 확장자만 제외)
    ///   - 폴더 → 전체 선택
    public static func initialSelectionRange(for displayName: String, isFolder: Bool) -> NSRange {
        let nsDisplayName = displayName as NSString
        let fullRange = NSRange(location: 0, length: nsDisplayName.length)

        // 폴더는 전체 선택
        if isFolder {
            return fullRange
        }

        // "."으로 시작하고 나머지에 "."이 없으면 dotfile → 전체 선택
        if displayName.hasPrefix(".") {
            let afterDot = String(displayName.dropFirst())
            if !afterDot.contains(".") {
                return fullRange
            }
        }

        // 마지막 "."의 위치 찾기
        let lastDotRange = nsDisplayName.range(of: ".", options: .backwards, range: fullRange)
        // "."이 첫 글자가 아니면 basename 선택
        if lastDotRange.location != NSNotFound, lastDotRange.location > 0 {
            return NSRange(location: 0, length: lastDotRange.location)
        }

        // "."이 없으면 전체 선택
        return fullRange
    }
}
