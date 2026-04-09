---
interaction_id: "CTM-001-reorder_content_tab"
interaction_type: "command"
feature: "Handle Content Tab"
category_key: "CTM"
feature_id: "CTM-001"
status: "준비 완료"
summary: "해당 Content Tab의 순서를 재배치"
related_region: "file_manager_window.sidebar.sidebar_body.content_tabs_area"
menu: "-"
shortcut: "-"
---

# Reorder Content Tab

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 2개 이상의 Content Tab이 열린 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 재배치 중인 Content Tab을 다른 창으로 이동시키는 경우

## Acceptance Criteria

- [ ] <<AI>> Content Tab이 2개 이상 열려 있을 때, 사용자가 해당 인터랙션을 호출하면, 드래그
      시작·종료 위치에 따라 Content Tab List 내 순서가 새로운 위치로 재배치됨.
- [ ] <<AI>> 탭을 드래그하는 중 다른 동작으로 탭이 닫히거나 이동된 경우, 사용자가 해당 인터랙션을
      마무리하면, 실제 남아 있는 탭들에 대해서만 일관된 순서가 유지됨

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `196`
