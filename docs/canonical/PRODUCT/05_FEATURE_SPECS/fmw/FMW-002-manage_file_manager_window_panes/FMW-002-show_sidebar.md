---
interaction_id: "FMW-002-show_sidebar"
interaction_type: "command"
feature: "Manage File Manager Window Panes"
category_key: "FMW"
feature_id: "FMW-002"
status: "배포 완료"
summary: "Sidebar를 File Manager의 좌측 영역에 고정되게 표시"
related_region: "file_manager_window.sidebar"
menu: "view_menu"
shortcut: "⌘⌃S"
---

# Show Sidebar

## Intent

- 숨겨진 Sidebar를 File Manager Window 좌측에 고정 표시해 저장소와 작업 진입점을 다시 노출한다.

## Trigger / Entry Points

- `view_menu`의 Show Sidebar 항목
- `⌘⌃S` 단축키
- Sidebar toggle 컨트롤

## Preconditions

- Sidebar가 `sidebar_hidden` 또는 `sidebar_transient` 상태다.

## Expected Outcome

- Sidebar가 좌측 패인으로 고정 표시되고 `sidebar_visible` 상태가 된다.

## State Changes

- Sidebar 표시 상태를 갱신하고 Content Pane 가용 너비를 재계산한다.
- Inspector Pane 표시 상태는 변경하지 않는다.
- 이 인터랙션은 [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)의 `sidebar_visible` 상태 어휘를 따른다.

## User-visible Feedback

- Sidebar가 좌측에 나타나고 메뉴/toggle 상태가 표시 중으로 갱신된다.

## Edge Cases / Failure Handling

- 현재 창 너비가 Sidebar 최소 너비보다 작으면 창 너비를 늘리거나 Content Pane 최소 너비를 보존하는 방향으로 레이아웃을 보정한다.
- 이미 표시 중이면 중복 표시 동작을 실행하지 않는다.

## Acceptance Criteria

- [ ] Sidebar가 숨김 상태일 때 사용자가 Show Sidebar를 실행하면, Sidebar는 `sidebar_visible` 상태로 고정 표시되어야 한다.
- [ ] Sidebar 표시 후 Content Pane은 최소 사용 가능 너비를 유지해야 한다.
- [ ] Show Sidebar는 Inspector Pane의 표시 상태를 변경하지 않아야 한다.

## Permissions / Dependencies

- FMW layout engine과 Sidebar minimum width 정책에 의존한다.

## Observability / Analytics

- `fmw.sidebar_shown` 이벤트에 이전 상태와 최종 너비를 기록한다.

## Related Interactions

- [FMW-002-adjust_inspector_pane_width](FMW-002-adjust_inspector_pane_width.md)
- [FMW-002-adjust_sidebar_width](FMW-002-adjust_sidebar_width.md)
- [FMW-002-draw_hidden_sidebar](FMW-002-draw_hidden_sidebar.md)
- [FMW-002-hide_inspector_pane](FMW-002-hide_inspector_pane.md)
- [FMW-002-hide_sidebar](FMW-002-hide_sidebar.md)
- [FMW-002-show_inspector_pane](FMW-002-show_inspector_pane.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:10`
- Flows: [file_manager_window_control_flow.md](../flows/file_manager_window_control_flow.md)
- Contract: [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)
