import Foundation
import VoyagerEntitiesEntry
import VoyagerShared

/// 타자 탐색 입력이 커밋된 한 글자일 때, 현재 표시 순서와 현재 단일 선택을 기준으로 다음 대상을 결정하는 순수 헬퍼.
public enum EntryViewLayoutTypeScrollMatcher {
    /// 입력을 정확히 한 그래프로 검증한 뒤, 전달된 `entries` 순서에서 이름의 첫 그래프가 입력 그래프와
    /// 정규화 동등한 엔트리의 id를 결정한다. 동일 logical id가 여러 번 투영되면 first visible occurrence만
    /// 참여한다. `currentSelectionID`가 match 목록에 있으면 그 다음 match를 반환하고 목록 끝에서는 첫 match로
    /// wrap한다. selection이 없거나 match 목록에 없으면 첫 match를 반환한다. 매칭이 없거나 입력이 유효한
    /// 단일 그래프가 아니면 `nil`을 반환한다.
    public static func selectionTargetID(
        in entries: [EntryModel],
        inputText: String,
        currentSelectionID: EntryModel.ID?,
    ) -> EntryModel.ID? {
        // 입력이 정확히 한 그래프가 아니면 무효 — prefix 자르지 않는다.
        guard let committed = CommittedTypeScrollInput.character(from: inputText) else { return nil }

        let normalizedInput = normalize(committed)

        var seenIDs = Set<EntryModel.ID>()
        var matches: [EntryModel.ID] = []
        matches.reserveCapacity(entries.count)
        for entry in entries {
            guard seenIDs.insert(entry.id).inserted else { continue }
            guard let firstCharacter = entry.name.first else { continue }
            if normalize(String(firstCharacter)) == normalizedInput {
                matches.append(entry.id)
            }
        }

        guard !matches.isEmpty else { return nil }

        if let currentSelectionID,
           let anchorIndex = matches.firstIndex(of: currentSelectionID)
        {
            return matches[(anchorIndex + 1) % matches.count]
        }
        return matches[0]
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
