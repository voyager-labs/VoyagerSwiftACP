---
interaction_id: "FMW-002-show_inspector_pane"
interaction_type: "command"
feature: "Manage File Manager Window Panes"
category_key: "FMW"
feature_id: "FMW-002"
status: "기획 완료"
summary: "Inspector Pane을 File Manager의 우측 영역에 고정되게 표시"
related_region: "file_manager_window.inspector_pane"
menu: "view_menu"
shortcut: "-"
---

# Show Inspector Pane

## Intent

- Inspector Pane을 File Manager Window 우측에 고정 표시해 선택 항목의 보조 작업 영역을 노출한다.

## Trigger / Entry Points

- `view_menu`의 Show Inspector 항목
- Inspector toggle 컨트롤 또는 관련 커맨드

## Preconditions

- Inspector Pane이 `inspector_hidden` 상태다.

## Expected Outcome

- Inspector Pane이 우측 패인으로 고정 표시되고 `inspector_visible` 상태가 된다.

## State Changes

- Inspector Pane 표시 상태를 갱신하고 Content Pane 가용 너비를 재계산한다.
- Sidebar 표시 상태는 변경하지 않는다.
- 이 인터랙션은 [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)의 `inspector_visible` 상태 어휘를 따른다.

## User-visible Feedback

- Inspector Pane이 우측에 나타나고 관련 메뉴/toggle 상태가 표시 중으로 갱신된다.

## Edge Cases / Failure Handling

- 현재 창 너비가 Inspector Pane 최소 너비보다 작으면 창 너비 또는 Content Pane 영역을 보정한다.
- 이미 표시 중이면 중복 표시 동작을 실행하지 않는다.

## Acceptance Criteria

- [ ] Inspector Pane이 숨김 상태일 때 사용자가 Show Inspector Pane을 실행하면, Inspector Pane은 `inspector_visible` 상태가 되어야 한다.
- [ ] Inspector Pane 표시 후 Content Pane은 최소 사용 가능 너비를 유지해야 한다.
- [ ] Show Inspector Pane은 Sidebar 표시 상태를 변경하지 않아야 한다.

## Permissions / Dependencies

- Inspector Pane mode restoration과 FMW layout minimum width 정책에 의존한다.

## Observability / Analytics

- `fmw.inspector_shown` 이벤트에 이전 상태와 복원된 mode를 기록한다.

## Related Interactions

- [FMW-002-adjust_inspector_pane_width](FMW-002-adjust_inspector_pane_width.md)
- [FMW-002-adjust_sidebar_width](FMW-002-adjust_sidebar_width.md)
- [FMW-002-draw_hidden_sidebar](FMW-002-draw_hidden_sidebar.md)
- [FMW-002-hide_inspector_pane](FMW-002-hide_inspector_pane.md)
- [FMW-002-hide_sidebar](FMW-002-hide_sidebar.md)
- [FMW-002-show_sidebar](FMW-002-show_sidebar.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:14`
- Flows: [file_manager_window_control_flow.md](../flows/file_manager_window_control_flow.md)
- Contract: [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)
