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

- 표시 중인 Sidebar의 너비를 허용 범위 안에서 조정한다.

## Trigger / Entry Points

- 사용자가 Sidebar와 Content Pane 사이 divider를 드래그한 경우

## Preconditions

- Sidebar가 `sidebar_visible` 상태다.

## Expected Outcome

- Sidebar 너비가 최소·최대 범위 안에서 변경되고 `sidebar_resized` 상태가 된다.

## State Changes

- Sidebar width preference를 갱신하고 Content Pane 가용 너비를 재계산한다.
- 허용 범위를 벗어난 값은 저장하지 않는다.
- 이 인터랙션은 [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)의 `sidebar_resized` 상태 어휘를 따른다.

## User-visible Feedback

- 드래그 중 Sidebar와 Content Pane 경계가 실시간으로 이동한다.
- 최소 또는 최대 한계에 도달하면 divider가 더 이상 같은 방향으로 이동하지 않는다.

## Edge Cases / Failure Handling

- 최소 너비 이하로 계속 줄이면 Hide Sidebar로 전환할 수 있는 임계값을 적용한다.
- 너비 조정 중 Hide Sidebar가 호출되면 조정 gesture를 종료하고 `sidebar_hidden` 상태를 우선한다.

## Acceptance Criteria

- [ ] Sidebar가 표시 중일 때 사용자가 divider를 드래그하면, Sidebar는 허용 범위 안에서만 `sidebar_resized` 상태로 갱신되어야 한다.
- [ ] 최소 허용값 아래로 줄이려 하면, 앱은 최소 너비를 유지하거나 명시적 hide 임계값에서 Sidebar를 숨겨야 한다.
- [ ] Sidebar 너비 변경은 Inspector Pane 너비를 직접 변경하지 않아야 한다.

## Permissions / Dependencies

- Sidebar minimum/maximum width policy와 FMW layout recalculation에 의존한다.

## Observability / Analytics

- `fmw.sidebar_resized` 이벤트에 최종 width, clamp 여부, hide 전환 여부를 기록한다.

## Related Interactions

- [FMW-002-adjust_inspector_pane_width](FMW-002-adjust_inspector_pane_width.md)
- [FMW-002-draw_hidden_sidebar](FMW-002-draw_hidden_sidebar.md)
- [FMW-002-hide_inspector_pane](FMW-002-hide_inspector_pane.md)
- [FMW-002-hide_sidebar](FMW-002-hide_sidebar.md)
- [FMW-002-show_inspector_pane](FMW-002-show_inspector_pane.md)
- [FMW-002-show_sidebar](FMW-002-show_sidebar.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:12`
- Flows: [file_manager_window_control_flow.md](../flows/file_manager_window_control_flow.md)
- Contract: [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)
