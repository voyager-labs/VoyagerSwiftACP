---
interaction_id: "FMW-001-minimize_file_manager_window"
interaction_type: "command"
feature: "Control File Manager Window"
category_key: "FMW"
feature_id: "FMW-001"
status: "배포 완료"
summary: "해당 File Manager 창을 macOS Dock으로 최소화"
related_region: "file_manager_window"
menu: "window_menu"
shortcut: "⌘M"
---

# Minimize File Manager Window

## Intent

- 활성 File Manager Window를 Dock으로 최소화해 화면 공간을 비운다.

## Trigger / Entry Points

- `window_menu`의 Minimize 항목
- `⌘M` 단축키
- 창 traffic light의 minimize 버튼

## Preconditions

- 활성 File Manager Window가 최소화 가능한 상태다.

## Expected Outcome

- 대상 창은 Dock으로 내려가고 `minimized` 상태가 된다.

## State Changes

- 창 세션과 내부 작업 상태는 유지하며 화면 표시 상태만 최소화한다.
- 이 인터랙션은 [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)의 `minimized` 상태 어휘를 따른다.

## User-visible Feedback

- macOS 최소화 애니메이션이 표시된다.
- 최소화가 불가능하면 창을 그대로 두고 실패 사유를 표시한다.

## Edge Cases / Failure Handling

- 이미 최소화된 창에 요청이 반복되면 상태를 변경하지 않는다.
- 전체 화면 Space에서 최소화 요청이 들어오면 OS 정책에 따라 전체 화면을 벗어난 뒤 최소화될 수 있다.

## Acceptance Criteria

- [ ] 활성 창이 최소화 가능할 때 사용자가 Minimize를 실행하면, 대상 창은 `minimized` 상태가 되어야 한다.
- [ ] 최소화 후에도 창 세션과 페이지 상태는 유지되어야 한다.
- [ ] 최소화가 실패하면 대상 창은 기존 표시 상태를 유지해야 한다.

## Permissions / Dependencies

- macOS window minimize API에 의존한다.

## Observability / Analytics

- `fmw.window_minimize_requested`, `fmw.window_minimized`, `fmw.window_minimize_failed` 이벤트를 기록한다.

## Related Interactions

- [FMW-001-adjust_file_manager_window_size](FMW-001-adjust_file_manager_window_size.md)
- [FMW-001-close_file_manager_window](FMW-001-close_file_manager_window.md)
- [FMW-001-enter_full_screen_for_file_manager_window](FMW-001-enter_full_screen_for_file_manager_window.md)
- [FMW-001-exit_full_screen_for_file_manager_window](FMW-001-exit_full_screen_for_file_manager_window.md)
- [FMW-001-keep_file_manager_window_on_top](FMW-001-keep_file_manager_window_on_top.md)
- [FMW-001-open_new_file_manager_window](FMW-001-open_new_file_manager_window.md)
- [FMW-001-quit_voyager](FMW-001-quit_voyager.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:7`
- Flows: [file_manager_window_control_flow.md](../flows/file_manager_window_control_flow.md)
- Contract: [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)
