---
interaction_id: "FMW-002-hide_inspector_pane"
interaction_type: "command"
feature: "Manage File Manager Window Panes"
category_key: "FMW"
feature_id: "FMW-002"
status: "기획 완료"
summary: "Inspector Pane을 File Manage에서 보이지 않게 숨김"
related_region: "file_manager_window.inspector_pane"
menu: "view_menu"
shortcut: "-"
---

# Hide Inspector Pane

## Intent

- Inspector Pane을 숨겨 메인 Content Pane의 가용 영역을 넓힌다.

## Trigger / Entry Points

- `view_menu`의 Hide Inspector 항목
- Inspector toggle 컨트롤 또는 관련 커맨드

## Preconditions

- Inspector Pane이 `inspector_visible` 상태다.

## Expected Outcome

- Inspector Pane은 보이지 않게 되고 `inspector_hidden` 상태가 된다.

## State Changes

- Inspector Pane 표시 상태를 숨김으로 갱신하고 마지막 mode와 너비를 보존한다.
- Sidebar와 현재 페이지 상태는 변경하지 않는다.
- 이 인터랙션은 [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)의 `inspector_hidden` 상태 어휘를 따른다.

## User-visible Feedback

- Inspector Pane이 사라지고 관련 메뉴/toggle 상태가 숨김으로 갱신된다.

## Edge Cases / Failure Handling

- Inspector Pane 안에 포커스가 있으면 숨김 후 포커스를 Content Pane 또는 안전한 기본 위치로 이동한다.
- 이미 숨김 상태이면 새 상태 변경을 만들지 않는다.

## Acceptance Criteria

- [ ] Inspector Pane이 표시 중일 때 사용자가 Hide Inspector Pane을 실행하면, Inspector Pane은 `inspector_hidden` 상태가 되어야 한다.
- [ ] Inspector Pane을 숨겨도 현재 페이지와 Sidebar 상태는 유지되어야 한다.
- [ ] Inspector Pane의 마지막 mode와 너비는 다음 표시를 위해 보존되어야 한다.

## Permissions / Dependencies

- FMW focus management와 Inspector Pane preference persistence에 의존한다.

## Observability / Analytics

- `fmw.inspector_hidden` 이벤트에 이전 mode와 보존된 너비를 기록한다.

## Related Interactions

- [FMW-002-adjust_inspector_pane_width](FMW-002-adjust_inspector_pane_width.md)
- [FMW-002-adjust_sidebar_width](FMW-002-adjust_sidebar_width.md)
- [FMW-002-draw_hidden_sidebar](FMW-002-draw_hidden_sidebar.md)
- [FMW-002-hide_sidebar](FMW-002-hide_sidebar.md)
- [FMW-002-show_inspector_pane](FMW-002-show_inspector_pane.md)
- [FMW-002-show_sidebar](FMW-002-show_sidebar.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:15`
- Flows: [file_manager_window_control_flow.md](../flows/file_manager_window_control_flow.md)
- Contract: [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)
