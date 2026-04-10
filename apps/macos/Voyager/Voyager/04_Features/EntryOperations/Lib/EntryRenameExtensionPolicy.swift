import Foundation

public enum EntryRenameExtensionTransition: Equatable {
    case none
    case added
    case removed
    case changed
}

public enum EntryRenameExtensionPolicy {
    /// 확장자 변경 여부 판정
    /// - Parameters:
    ///   - oldName: 이전 파일명
    ///   - newName: 새 파일명
    ///   - isFolder: 폴더 여부 (폴더는 항상 .none)
    /// - Returns: 확장자 변경 상태
    /// - Note: dotfile(`.env`)은 extensionless로 취급
    public static func extensionTransition(
        from oldName: String,
        to newName: String,
        isFolder: Bool,
    ) -> EntryRenameExtensionTransition {
        // 폴더는 항상 none
        if isFolder {
            return .none
        }

        let oldExt = finalExtension(of: oldName)
        let newExt = finalExtension(of: newName)

        if oldExt == newExt {
            return .none
        } else if oldExt.isEmpty, !newExt.isEmpty {
            return .added
        } else if !oldExt.isEmpty, newExt.isEmpty {
            return .removed
        } else {
            return .changed
        }
    }

    /// 파일명에서 마지막 확장자 추출
    /// - Parameter name: 파일명
    /// - Returns: 마지막 "." 이후 문자열 (dotfile은 빈 문자열 반환)
    private static func finalExtension(of name: String) -> String {
        // "."으로 시작하고 나머지에 "."이 없으면 extensionless
        if name.hasPrefix(".") {
            let afterDot = String(name.dropFirst())
            if !afterDot.contains(".") {
                return ""
            }
        }

        // 마지막 "." 이후 반환
        if let lastDotIndex = name.lastIndex(of: ".") {
            let dotPosition = name.distance(from: name.startIndex, to: lastDotIndex)
            // "."이 첫 글자가 아니면 확장자 반환
            if dotPosition > 0 {
                return String(name[name.index(after: lastDotIndex)...])
            }
        }

        return ""
    }
}
