---
interaction_id: "RCL-001-open_collection_filter_composer"
interaction_type: "command"
feature: "Define Collection Filter"
category_key: "RCL"
feature_id: "RCL-001"
status: "배포 완료"
summary: "Entries View 상단에서 Collection Filter Composer를 열어 현재 콜렉션의 스코프·조건을 편집 가능 상태로 전환"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "Edit"
shortcut: "⌘F"
---

# Open Collection Filter Composer

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 현재 페이지가 필터 편집을 지원하는 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 이미 Collection Filter Composer가 열린 상태에서 호출되는 경우
- 미저장 필터 변경이 존재하는 경우

## Acceptance Criteria

- [ ] 현재 페이지가 필터 편집을 지원하는 상태일 때, 사용자가 해당 인터랙션을 호출하면, Collection
      Filter Composer가 표시되고 Filter Query 입력 필드로 포커스가 이동함
- [ ] Composer가 이미 열린 상태일 때, 사용자가 해당 인터랙션을 호출하면, Filter Query 입력 필드로
      포커스가 이동함
- [ ] 미저장 필터 변경이 존재하는 상태일 때, 사용자가 해당 인터랙션을 호출하면, 미저장 변경이 반영된
      Composer를 표시함

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `101`
