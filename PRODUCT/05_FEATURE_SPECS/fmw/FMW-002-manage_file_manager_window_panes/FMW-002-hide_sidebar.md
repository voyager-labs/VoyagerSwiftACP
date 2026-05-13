---
interaction_id: "FMW-002-hide_sidebar"
interaction_type: "command"
feature: "Manage File Manager Window Panes"
category_key: "FMW"
feature_id: "FMW-002"
status: "배포 완료"
summary: "Sidebar를 File Manager에서 보이지 않게 숨김"
related_region: "file_manager_window.sidebar"
menu: "view_menu"
shortcut: "⌘⌃S"
---

# Hide Sidebar

## Intent

- Sidebar를 숨겨 File Manager Window의 Content Pane 가용 영역을 넓힌다.

## Trigger / Entry Points

- `view_menu`의 Hide Sidebar 항목
- `⌘⌃S` 단축키
- Sidebar toggle 컨트롤

## Preconditions

- Sidebar가 `sidebar_visible` 또는 `sidebar_transient` 상태다.

## Expected Outcome

- Sidebar는 보이지 않게 되고 `sidebar_hidden` 상태가 된다.

## State Changes

- Sidebar 표시 상태를 숨김으로 갱신하고 Content Pane 가용 너비를 재계산한다.
- Sidebar의 마지막 고정 너비 값은 이후 표시 복원을 위해 보존한다.
- 이 인터랙션은 [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)의 `sidebar_hidden` 상태 어휘를 따른다.

## User-visible Feedback

- Sidebar가 사라지고 메뉴/toggle 상태가 숨김으로 갱신된다.

## Edge Cases / Failure Handling

- 이미 숨김 상태이면 새 상태 변경을 만들지 않는다.
- Sidebar 안에 포커스가 있을 때 숨기면 포커스를 Content Pane 또는 안전한 기본 위치로 이동한다.

## Acceptance Criteria

- [ ] Sidebar가 표시 중일 때 사용자가 Hide Sidebar를 실행하면, Sidebar는 `sidebar_hidden` 상태가 되어야 한다.
- [ ] Sidebar를 숨겨도 현재 페이지와 Inspector Pane 상태는 유지되어야 한다.
- [ ] Sidebar 포커스 중 숨김이 실행되면, 키보드 포커스는 보이는 영역으로 이동해야 한다.

## Permissions / Dependencies

- FMW focus management와 Sidebar width persistence에 의존한다.

## Observability / Analytics

- `fmw.sidebar_hidden` 이벤트에 이전 상태와 보존된 너비를 기록한다.

## Related Interactions

- [FMW-002-adjust_inspector_pane_width](FMW-002-adjust_inspector_pane_width.md)
- [FMW-002-adjust_sidebar_width](FMW-002-adjust_sidebar_width.md)
- [FMW-002-draw_hidden_sidebar](FMW-002-draw_hidden_sidebar.md)
- [FMW-002-hide_inspector_pane](FMW-002-hide_inspector_pane.md)
- [FMW-002-show_inspector_pane](FMW-002-show_inspector_pane.md)
- [FMW-002-show_sidebar](FMW-002-show_sidebar.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:11`
- Flows: [file_manager_window_control_flow.md](../flows/file_manager_window_control_flow.md)
- Contract: [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)
