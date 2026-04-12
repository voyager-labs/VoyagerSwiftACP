---
interaction_id: "FMW-002-adjust_sidebar_width"
interaction_type: "input"
feature: "Manage File Manager Window Panes"
category_key: "FMW"
feature_id: "FMW-002"
status: "배포 완료"
summary: "Sidebar의 Width를 최소-최대 범위 내에서 조정"
related_region: "file_manager_window.sidebar"
menu: "-"
shortcut: "-"
---

# Adjust Sidebar Width

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- Sidebar가 표시 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 사용자가 최소 너비 허용값 이하로 조정하려는 경우
- 사용자가 최대 너비 허용값 이상으로 조정하려는 경우
- 너비 조정 중 Hide Sidebar가 호출되는 경우

## Acceptance Criteria

- [ ] Sidebar가 표시 상태일 때, 사용자가 해당 인터랙션을 호출하면, Sidebar Width가 정의된 최소-최대
      범위 내에서만 변경됨
- [ ] Sidebar 너비를 최소 허용값 이하로 줄이려는 상태에서 사용자가 해당 인터랙션을 호출하면, Hide
      Sidebar 인터랙션을 호출함
- [ ] Sidebar 너비를 늘리려 할 때, 특정한 값에 도달한다면, 해당 값에서 더 이상 증가하지 않음

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `12`
