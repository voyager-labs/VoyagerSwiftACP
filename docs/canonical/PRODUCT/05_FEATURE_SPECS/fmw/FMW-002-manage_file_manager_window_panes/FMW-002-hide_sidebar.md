---
interaction_id: "FMW-002-hide_sidebar"
interaction_type: "command"
feature: "Manage File Manager Window Panes"
category_key: "FMW"
feature_id: "FMW-002"
status: "배포 완료"
summary: "Sidebar를 File Manager에서 보이지 않게 숨김"
related_region: "file_manager_window.sidebar"
menu: "View"
shortcut: "⌘⌃S"
---

# Hide Sidebar

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

- 사용자가 Sidebar 내부 요소와 인터랙션 중 호출되는 경우

## Acceptance Criteria

- [ ] Sidebar가 표시 상태일 때, 사용자가 해당 인터랙션을 호출하면, Sidebar가 숨김 상태로 전환되고
      Content Pane이 좌측으로 확장됨
- [ ] 사용자가 Sidebar 내부 요소와 인터랙션 중일 때, 사용자가 해당 인터랙션을 호출하면, 현재
      상호작용을 안전하게 종료한 뒤 후속 처리를 함

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `11`
