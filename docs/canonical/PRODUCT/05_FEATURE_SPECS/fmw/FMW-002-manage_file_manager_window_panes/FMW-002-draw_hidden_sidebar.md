---
interaction_id: "FMW-002-draw_hidden_sidebar"
interaction_type: "command"
feature: "Manage File Manager Window Panes"
category_key: "FMW"
feature_id: "FMW-002"
status: "기획 완료"
summary: "숨겨진 Sidebar를 File Manager의 좌측 영역에 일시적으로 표시"
related_region: "file_manager_window.sidebar"
menu: "-"
shortcut: "-"
---

# Draw Hidden Sidebar

## Intent

- 숨겨진 Sidebar를 임시 drawer로 열어 고정 표시 없이 빠르게 접근하게 한다.

## Trigger / Entry Points

- Sidebar가 숨겨진 상태에서 edge reveal gesture 또는 임시 Sidebar 호출 명령을 실행한 경우

## Preconditions

- Sidebar가 `sidebar_hidden` 상태이고 현재 창이 임시 drawer를 표시할 수 있다.

## Expected Outcome

- Sidebar가 임시 overlay/drawer로 표시되고 `sidebar_transient` 상태가 된다.

## State Changes

- 고정 Sidebar 표시 설정은 변경하지 않는다.
- drawer가 닫히면 Sidebar는 다시 `sidebar_hidden` 상태로 돌아간다.
- 이 인터랙션은 [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)의 `sidebar_transient` 상태 어휘를 따른다.

## User-visible Feedback

- Sidebar가 좌측에서 임시로 나타나며 Content Pane 위에 겹쳐 보일 수 있다.
- drawer 밖을 클릭하거나 포커스가 벗어나면 닫힘 피드백 없이 사라진다.

## Edge Cases / Failure Handling

- 이미 Sidebar가 고정 표시 중이면 transient drawer를 만들지 않는다.
- 창 너비가 너무 좁으면 drawer 폭을 허용 최소값으로 제한한다.

## Acceptance Criteria

- [ ] Sidebar가 숨김 상태일 때 사용자가 Draw Hidden Sidebar를 실행하면, Sidebar는 `sidebar_transient` 상태로 임시 표시되어야 한다.
- [ ] 임시 Sidebar가 닫히면 고정 표시 설정은 바뀌지 않고 `sidebar_hidden` 상태로 돌아가야 한다.
- [ ] Sidebar가 이미 `sidebar_visible` 상태이면 transient drawer를 추가로 만들지 않아야 한다.

## Permissions / Dependencies

- Sidebar drawer overlay, focus dismissal, edge gesture handling에 의존한다.

## Observability / Analytics

- `fmw.sidebar_drawer_opened`, `fmw.sidebar_drawer_dismissed` 이벤트를 기록한다.

## Related Interactions

- [FMW-002-adjust_inspector_pane_width](FMW-002-adjust_inspector_pane_width.md)
- [FMW-002-adjust_sidebar_width](FMW-002-adjust_sidebar_width.md)
- [FMW-002-hide_inspector_pane](FMW-002-hide_inspector_pane.md)
- [FMW-002-hide_sidebar](FMW-002-hide_sidebar.md)
- [FMW-002-show_inspector_pane](FMW-002-show_inspector_pane.md)
- [FMW-002-show_sidebar](FMW-002-show_sidebar.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:13`
- Flows: [file_manager_window_control_flow.md](../flows/file_manager_window_control_flow.md)
- Contract: [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)
