---
interaction_id: "FMW-002-show_sidebar"
interaction_type: "command"
feature: "Manage File Manager Window Panes"
category_key: "FMW"
feature_id: "FMW-002"
status: "배포 완료"
summary: "Sidebar를 File Manager의 좌측 영역에 고정되게 표시"
related_region: "file_manager_window.sidebar"
menu: "View"
shortcut: "⌘⌃S"
---

# Show Sidebar

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- Sidebar가 숨김 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 현재 창 너비가 표시되는 Sidebar의 설정된 너비보다 작은 경우

## Acceptance Criteria

- [ ] Sidebar가 숨김 상태이고 창 너비가 Sidebar를 표시하기에 충분할 때, 사용자가 해당 인터랙션을
      호출하면, Sidebar가 File Manager 좌측 영역에 기본 너비로 고정되어 표시됨
- [ ] 창 너비가 Sidebar 최소 너비보다 작은 상태일 때, 사용자가 해당 인터랙션을 호출하면, Sidebar의
      최소 너비만큼 Window의 너비를 늘림

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `10`
