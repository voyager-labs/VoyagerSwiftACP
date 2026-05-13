---
interaction_id: "FMW-002-adjust_inspector_pane_width"
interaction_type: "input"
feature: "Manage File Manager Window Panes"
category_key: "FMW"
feature_id: "FMW-002"
status: "기획 완료"
summary: "Inspector Pane의 Width를 최소-최대 범위 내에서 조정"
related_region: "file_manager_window.inspector_pane"
menu: "-"
shortcut: "-"
---

# Adjust Inspector Pane Width

## Intent

- 표시 중인 Inspector Pane의 너비를 허용 범위 안에서 조정한다.

## Trigger / Entry Points

- 사용자가 Content Pane과 Inspector Pane 사이 divider를 드래그한 경우

## Preconditions

- Inspector Pane이 `inspector_visible` 상태다.

## Expected Outcome

- Inspector Pane 너비가 최소·최대 범위 안에서 변경되고 `inspector_resized` 상태가 된다.

## State Changes

- Inspector Pane width preference를 갱신하고 Content Pane 가용 너비를 재계산한다.
- 허용 범위를 벗어난 값은 저장하지 않는다.
- 이 인터랙션은 [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)의 `inspector_resized` 상태 어휘를 따른다.

## User-visible Feedback

- 드래그 중 Inspector Pane 경계가 실시간으로 이동한다.
- 최소 또는 최대 한계에 도달하면 divider가 더 이상 같은 방향으로 이동하지 않는다.

## Edge Cases / Failure Handling

- 최소 너비 이하로 계속 줄이면 Hide Inspector Pane 전환 임계값을 적용할 수 있다.
- 너비 조정 중 Hide Inspector Pane이 호출되면 조정 gesture를 종료하고 `inspector_hidden` 상태를 우선한다.

## Acceptance Criteria

- [ ] Inspector Pane이 표시 중일 때 사용자가 divider를 드래그하면, Inspector Pane은 허용 범위 안에서만 `inspector_resized` 상태로 갱신되어야 한다.
- [ ] 최소 허용값 아래로 줄이려 하면, 앱은 최소 너비를 유지하거나 명시적 hide 임계값에서 Inspector Pane을 숨겨야 한다.
- [ ] Inspector Pane 너비 변경은 Sidebar 너비를 직접 변경하지 않아야 한다.

## Permissions / Dependencies

- Inspector Pane minimum/maximum width policy와 FMW layout recalculation에 의존한다.

## Observability / Analytics

- `fmw.inspector_resized` 이벤트에 최종 width, clamp 여부, hide 전환 여부를 기록한다.

## Related Interactions

- [FMW-002-adjust_sidebar_width](FMW-002-adjust_sidebar_width.md)
- [FMW-002-draw_hidden_sidebar](FMW-002-draw_hidden_sidebar.md)
- [FMW-002-hide_inspector_pane](FMW-002-hide_inspector_pane.md)
- [FMW-002-hide_sidebar](FMW-002-hide_sidebar.md)
- [FMW-002-show_inspector_pane](FMW-002-show_inspector_pane.md)
- [FMW-002-show_sidebar](FMW-002-show_sidebar.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:16`
- Flows: [file_manager_window_control_flow.md](../flows/file_manager_window_control_flow.md)
- Contract: [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)
