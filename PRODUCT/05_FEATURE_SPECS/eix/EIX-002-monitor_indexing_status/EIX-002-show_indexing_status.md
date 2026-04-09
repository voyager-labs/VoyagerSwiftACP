---
interaction_id: "EIX-002-show_indexing_status"
interaction_type: "display"
feature: "Monitor Indexing Status"
category_key: "EIX"
feature_id: "EIX-002"
status: "준비 완료"
summary: "인덱싱 큐 길이, 진행률에 대한 엔트리 인덱싱 상태를 요약해 표시"
related_region: "file_manager_window.sidebar.sidebar_footer"
menu: "-"
shortcut: "-"
---

# Show Indexing Status

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 엔트리 인덱싱이 진행 중인 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 엔트리 인덱싱이 진행 중인데 인덱싱 상태 요약 표시가 노출되지 않는 경우
- 인덱싱 상태 요약 표시가 노출된 상태에서 인덱싱이 완료·일시 중지·실패로 전환되는 경우

## Acceptance Criteria

- [ ] 엔트리 인덱싱이 진행 중인 상태일 때, 시스템이 인덱싱 상태를 집계하면, 인덱싱 큐 길이와
      진행률을 요약해 표시함
- [ ] 엔트리 인덱싱이 진행 중인 상태일 때, 시스템이 인덱싱 상태를 갱신하면, 요약 표시의 큐
      길이·진행률 값을 최신 상태로 업데이트함
- [ ] 엔트리 인덱싱이 진행 중인 상태일 때, 인덱싱 상태 요약 표시가 노출되지 않는다면, 시스템이
      인덱싱 상태를 갱신해 요약 표시를 다시 노출함
- [ ] 인덱싱이 완료·일시 중지·실패로 전환될 때, 시스템이 상태 전환을 반영하면, 요약 표시를 전환된
      상태에 맞게 갱신함

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `73`
