---
interaction_id: "EIX-002-show_indexing_failures"
interaction_type: "display"
feature: "Monitor Indexing Status"
category_key: "EIX"
feature_id: "EIX-002"
status: "준비 완료"
summary: "인덱싱 실패 항목들을 나열하고, 각 항목의 실패 단계와 오류 요약을 표시"
related_region: "file_manager_window.sidebar.sidebar_footer"
menu: "-"
shortcut: "-"
---

# Show Indexing Failures

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 인덱싱 실패 항목이 존재하는 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 대상 엔트리가 삭제되었거나 경로가 변경되어 실패 항목의 표시 정보가 불완전한 경우
- 실패 항목의 오류 요약을 생성·조회할 수 없는 경우

## Acceptance Criteria

- [ ] 인덱싱 실패 항목이 존재하는 상태일 때, 시스템이 실패 항목 목록을 표시하면, 실패 항목들을
      리스트로 나열함
- [ ] 실패 항목 목록을 표시가 될 때, 대상 엔트리가 삭제되었거나 경로가 변경되어 표시 정보가
      불완전하다면, 마지막으로 기록된 식별 정보로 항목을 표시하고, 현재 정보 확인 불가 상태를 함께
      표시함
- [ ] 실패 항목 목록을 표시가 될 때, 실패 항목의 오류 요약을 생성·조회할 수 없다면, 오류 요약 대신
      요약 불가 상태를 표시하고 실패 단계는 표시함
- [ ] 실패 항목 목록 표시를 확인할 때, 사용자가 추가적인 인터랙션을 한다면, 각 항목별로 실패 단계와
      오류 요약을 확인할 수 있음

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `76`
