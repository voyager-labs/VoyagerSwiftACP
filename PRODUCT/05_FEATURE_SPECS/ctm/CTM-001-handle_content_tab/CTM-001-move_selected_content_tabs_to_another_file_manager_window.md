---
interaction_id: "CTM-001-move_selected_content_tabs_to_another_file_manager_window"
interaction_type: "command"
feature: "Handle Content Tab"
category_key: "CTM"
feature_id: "CTM-001"
status: "준비 완료"
summary: "선택한 Content Tab들을 다른 File Manager로 일괄 이동"
related_region: "file_manager_window.sidebar.sidebar_body.content_tabs_area"
menu: "-"
shortcut: "-"
---

# Move Selected Content Tabs to Another File Manager Window

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 2개 이상의 Content Tab이 열린 상태
- 1개 이상의 Content Tab이 지정된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

-   -

## Acceptance Criteria

- [ ] <<AI>> 둘 이상의 File Manager Window가 열려 있고 하나 이상의 Content Tab이 선택된 상태에서
      사용자가 해당 인터랙션을 호출하면, 선택된 모든 탭이 지정된 다른 File Manager Window의 Tab
      List로 이동하고 원래 창에서는 제거됨.
- [ ] <<AI>> 이동 처리 중 대상 File Manager Window가 닫히거나 유효하지 않게 된 경우, 사용자가 해당
      인터랙션을 호출하면, 이동을 수행하지 않고 원래 창 상태를 유지하거나 오류를 표시함.
- [ ] <<AI>> 대상 창에 동일 세션 탭이 이미 있는 상태에서 사용자가 해당 인터랙션을 호출하면, 중복
      세션 처리 정책에 따라 동작하고 실제 결과가 UI에 반영됨.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `204`
