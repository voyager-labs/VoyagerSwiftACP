import Foundation

/// file URL 또는 path string을 정규화된 filesystem path로 변환하는 순수 함수.
///
/// ComposerScopePathNormalization의 path 정규화와 동일한 `standardizingPath` 기반 접근을 사용하며,
/// 향후 두 정규화 로직을 통합할 수 있음.
public enum FilePathNormalizer {
    /// 입력을 정규화된 filesystem path로 변환한다.
    ///
    /// 정규화 규칙:
    /// 1. file URL(`file://`) → `URL.path`로 filesystem path 변환 (percent-encoded 문자 디코딩)
    /// 2. `standardizingPath`로 `.`, `..`, 중복 `/` 정규화
    /// 3. trailing slash 제거 (root `/`는 유지)
    /// 4. 빈/공백 입력 → 빈 문자열
    ///
    /// - Parameter input: file URL 또는 filesystem path 문자열
    /// - Returns: 정규화된 filesystem path
    public static func normalize(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let path: String
        if trimmed.hasPrefix("file://") {
            guard let url = URL(string: trimmed) else { return trimmed }
            path = url.path
        } else {
            path = trimmed
        }

        let standardized = (path as NSString).standardizingPath

        if standardized == "/" {
            return standardized
        }
        if standardized.hasSuffix("/") {
            return String(standardized.dropLast())
        }

        return standardized
    }
}
