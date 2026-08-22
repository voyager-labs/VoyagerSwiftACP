import Foundation

/// 커밋된 타자 입력에서 단일 "문자"(그래핌 클러스터)만 추출/검증하는 순수 헬퍼.
///
/// - 입력이 정확히 하나의 그래핌 클러스터이고,
/// - 공백(스페이스/탭/개행)이 아니며,
/// - 제어 문자(C0/C1 컨트롤)나 함수 키 영역(0xF700...0xF8FF) 스칼라를 포함하지 않을 때만
///   원본 문자열을 그대로 반환한다.
/// - 그 외(빈 문자열, 2개 이상 그래핌, 공백, 제어/함수 키 문자)는 `nil`을 반환한다.
/// - 절대 prefix로 자르지 않는다. 여러 그래핌이면 `nil`이다.
public enum CommittedTypeScrollInput {
    /// 커밋된 입력 문자열이 유효한 단일 문자이면 그대로, 아니면 `nil`.
    public static func character(from committedText: String) -> String? {
        // 그래핌 클러스터 수가 정확히 1이어야 한다 (prefix 자르기 금지).
        guard committedText.count == 1 else { return nil }

        // 공백(스페이스/탭/개행 등)은 유효한 입력이 아니다.
        guard !committedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        // 제어 문자(C0/C1) 또는 함수 키 영역(0xF700...0xF8FF) 스칼라가 있으면 유효하지 않다.
        let hasForbiddenScalar = committedText.unicodeScalars.contains { scalar in
            scalar.value < 0x20
                || (0x7F ... 0x9F).contains(scalar.value)
                || (0xF700 ... 0xF8FF).contains(scalar.value)
        }
        guard !hasForbiddenScalar else { return nil }

        return committedText
    }
}
