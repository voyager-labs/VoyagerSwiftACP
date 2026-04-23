---
interaction_id: "FMW-001-keep_file_manager_window_on_top"
interaction_type: "command"
feature: "Control File Manager Window"
category_key: "FMW"
feature_id: "FMW-001"
status: "준비 완료"
summary: "File Manager 창을 다른 앱보다 항상 위로 고정"
related_region: "file_manager_window"
menu: "Window"
shortcut: "-"
---

# Keep File Manager Window on Top

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- -

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- -

## Acceptance Criteria

- [ ] 대상 File Manager Window가 일반 창 상태일 때, 사용자가 해당 인터랙션을 호출하면, 해당 창이
      “항상 위” 상태로 전환되어 다른 일반 창보다 위에 유지됨
- [ ] 대상 File Manager Window이 이미 "항상 위" 상태 일 떄, 사용자가 해당 인터랙션을 다시 호출하면,
      해당 창은 일반 창 상태로 전환됨

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `8`
