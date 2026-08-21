import Foundation
import VoyagerEntitiesEntry
import VoyagerShared

/// 타자 스크롤 입력이 커밋된 한 글자일 때, 표시 순서상 첫 매칭 엔트리를 찾는 순수 헬퍼.
public enum EntryViewLayoutTypeScrollMatcher {
    /// 입력을 정확히 한 그래프로 검증한 뒤, 전달된 `entries` 순서에서 이름의 첫 그래프가
    /// 입력 그래프와 정규화 동등한 첫 엔트리의 id를 반환한다. 매칭이 없거나 입력이
    /// 유효한 단일 그래프가 아니면 `nil`을 반환한다.
    public static func firstMatchID(in entries: [EntryModel], inputText: String) -> EntryModel.ID? {
        // 입력이 정확히 한 그래프가 아니면 무효 — prefix 자르지 않는다.
        guard let committed = CommittedTypeScrollInput.character(from: inputText) else { return nil }

        let normalizedInput = normalize(committed).first

        for entry in entries {
            let normalizedName = normalize(entry.name).first
            if normalizedName == normalizedInput {
                return entry.id
            }
        }

        return nil
    }

    /// 대소문자·발음구별부호·전각/반각 폭 차이를 접고, NFC로 정규화해 첫 그래프 비교가
    /// NFD/NFC 동등까지 일관되게 동작하게 한다.
    private static func normalize(_ string: String) -> String {
        string
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: nil,
            )
            .precomposedStringWithCanonicalMapping
    }
}
