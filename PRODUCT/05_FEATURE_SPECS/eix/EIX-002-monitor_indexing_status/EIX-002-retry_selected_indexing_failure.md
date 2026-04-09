---
interaction_id: "EIX-002-retry_selected_indexing_failure"
interaction_type: "command"
feature: "Monitor Indexing Status"
category_key: "EIX"
feature_id: "EIX-002"
status: "준비 완료"
summary: "선택한 인덱싱 실패 항목의 인덱싱을 재시도"
related_region: "file_manager_window.sidebar.sidebar_footer"
menu: "-"
shortcut: "-"
---

# Retry Selected Indexing Failure

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 인덱싱 실패 항목이 선택된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 실패 원인이 지속되어 재시도가 반복 실패하는 경우
- 대상 엔트리가 삭제되었거나 경로가 변경되어 재시도가 불가능한 경우

## Acceptance Criteria

- [ ] 인덱싱 실패 항목이 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 시스템이 선택한 실패
      항목을 재시도 작업으로 등록하고 항목 상태를 재시도 진행 상태로 갱신함
- [ ] 실패 항목 인덱싱 재시도를 했을 때, 실패 원인이 지속되어 재시도가 반복 실패한다면, 실패 상태를
      유지하고 오류 요약을 최신 정보로 갱신함
- [ ] 실패 항목 인덱싱 재시도를 했을 때, 대상 엔트리가 삭제되었거나 경로가 변경되어 재시도가
      불가능하다면, 재시도 불가 사유를 기록하고 항목 상태를 실패로 유지함

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `77`
