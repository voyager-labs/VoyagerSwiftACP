---
interaction_id: "EAC-004-get_entry_info"
interaction_type: "command"
feature: "Edit System Property"
category_key: "EAC"
feature_id: "EAC-004"
status: "배포 완료"
summary: "선택한 Entry의 상세 정보 패널을 표시"
related_region: "file_manager_window.content_pane.page_container.page_mode_directory"
menu: "File"
shortcut: "⌘I"
---

# Get Entry Info

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 다중 선택 상태에서 일부 속성 집계가 지연되는 경우
- <<AI>> 선택된 Entry가 외부 변경으로 더 이상 존재하지 않는 경우

## Acceptance Criteria

- [ ] <<AI>> 하나 이상의 Entry가 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 선택한 Entry의
      상세 정보 패널을 표시함.
- [ ] <<AI>> 다중 선택 상태일 때, 시스템이 정보 패널을 표시하면, 공통 속성은 통합 표시하고 집계 값은
      계산 결과로 표시함.
- [ ] <<AI>> 선택된 Entry가 유효하지 않은 상태일 때, 사용자가 해당 인터랙션을 호출하면, 제한된
      정보만 표시하거나 표시를 중단하고 사유를 사용자에게 안내함.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `60`
