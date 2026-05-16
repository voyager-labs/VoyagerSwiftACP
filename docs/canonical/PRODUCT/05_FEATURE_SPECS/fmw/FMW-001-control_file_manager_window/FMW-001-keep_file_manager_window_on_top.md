---
interaction_id: "FMW-001-keep_file_manager_window_on_top"
interaction_type: "command"
feature: "Control File Manager Window"
category_key: "FMW"
feature_id: "FMW-001"
status: "준비 완료"
summary: "File Manager 창을 다른 앱보다 항상 위로 고정"
related_region: "file_manager_window"
menu: "window_menu"
shortcut: "-"
---

# Keep File Manager Window on Top

## Intent

- File Manager Window가 다른 앱 위에 유지될지 여부를 토글한다.

## Trigger / Entry Points

- `window_menu`의 Keep on Top 항목
- 창 관련 커맨드 또는 Command Palette에서 같은 명령을 실행한 경우

## Preconditions

- 대상 File Manager Window가 열려 있고 z-order 고정 상태를 변경할 수 있다.

## Expected Outcome

- 고정이 꺼져 있으면 `pinned` 상태가 되고, 켜져 있으면 `unpinned` 상태가 된다.

## State Changes

- 창의 z-order 정책만 변경하며 크기, 전체 화면, 패인 표시 상태는 변경하지 않는다.
- 이 인터랙션은 [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)의 `pinned`, `unpinned` 상태 어휘를 따른다.

## User-visible Feedback

- 메뉴 체크 상태 또는 창 표시 우선순위가 즉시 갱신된다.
- OS 정책상 고정할 수 없는 상태면 실패 피드백을 표시한다.

## Edge Cases / Failure Handling

- 전체 화면 상태에서는 macOS Space 정책이 우선하며 pin 상태는 일반 창으로 돌아왔을 때 적용될 수 있다.
- 여러 File Manager Window가 열려 있으면 활성 창에만 적용한다.

## Acceptance Criteria

- [ ] 활성 창이 `unpinned` 상태일 때 사용자가 Keep on Top을 실행하면, 대상 창은 `pinned` 상태가 되어야 한다.
- [ ] 활성 창이 `pinned` 상태일 때 같은 명령을 실행하면, 대상 창은 `unpinned` 상태가 되어야 한다.
- [ ] pin 토글은 창 크기와 패인 표시 상태를 변경하지 않아야 한다.

## Permissions / Dependencies

- macOS window level 제어 가능 여부에 의존한다.

## Observability / Analytics

- `fmw.window_pin_toggled`, `fmw.window_pinned`, `fmw.window_unpinned` 이벤트를 기록한다.

## Related Interactions

- [FMW-001-adjust_file_manager_window_size](FMW-001-adjust_file_manager_window_size.md)
- [FMW-001-close_file_manager_window](FMW-001-close_file_manager_window.md)
- [FMW-001-enter_full_screen_for_file_manager_window](FMW-001-enter_full_screen_for_file_manager_window.md)
- [FMW-001-exit_full_screen_for_file_manager_window](FMW-001-exit_full_screen_for_file_manager_window.md)
- [FMW-001-minimize_file_manager_window](FMW-001-minimize_file_manager_window.md)
- [FMW-001-open_new_file_manager_window](FMW-001-open_new_file_manager_window.md)
- [FMW-001-quit_voyager](FMW-001-quit_voyager.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:8`
- Flows: [file_manager_window_control_flow.md](../flows/file_manager_window_control_flow.md)
- Contract: [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)
