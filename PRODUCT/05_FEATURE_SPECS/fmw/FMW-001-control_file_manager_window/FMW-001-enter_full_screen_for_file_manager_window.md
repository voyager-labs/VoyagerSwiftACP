---
interaction_id: "FMW-001-enter_full_screen_for_file_manager_window"
interaction_type: "command"
feature: "Control File Manager Window"
category_key: "FMW"
feature_id: "FMW-001"
status: "배포 완료"
summary: "해당 File Manager 창을 전체 화면으로 전환"
related_region: "file_manager_window"
menu: "view_menu"
shortcut: "⌘⌃F"
---

# Enter Full Screen for File Manager Window

## Intent

- 활성 File Manager Window를 전체 화면으로 전환해 현재 작업 공간을 최대화한다.

## Trigger / Entry Points

- `view_menu`의 Enter Full Screen 항목
- `⌘⌃F` 단축키
- 창 traffic light의 전체 화면 버튼

## Preconditions

- 활성 File Manager Window가 일반 창 또는 전체 화면이 아닌 표시 상태다.

## Expected Outcome

- 대상 창은 macOS 전체 화면 Space로 이동하고 `full_screen` 상태가 된다.

## State Changes

- 창 표시 모드만 변경하며 페이지, 선택, Sidebar, Inspector Pane 상태는 보존한다.
- 이 인터랙션은 [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)의 `full_screen` 상태 어휘를 따른다.

## User-visible Feedback

- OS 전체 화면 전환 애니메이션이 표시된다.
- 전환이 불가능하면 현재 창 표시 상태를 유지하고 실패 사유를 표시한다.

## Edge Cases / Failure Handling

- 이미 전체 화면이면 새 전환을 만들지 않고 현재 `full_screen` 상태를 유지한다.
- macOS가 전체 화면 전환을 거부하면 기존 windowed 상태를 유지한다.

## Acceptance Criteria

- [ ] 활성 창이 일반 창 상태일 때 사용자가 Enter Full Screen을 실행하면, 대상 창은 `full_screen` 상태로 전환되어야 한다.
- [ ] 전체 화면 전환 후에도 Sidebar와 Inspector Pane의 기존 표시 상태는 보존되어야 한다.
- [ ] 이미 `full_screen` 상태에서 같은 인터랙션이 호출되면, 중복 전환을 실행하지 않아야 한다.

## Permissions / Dependencies

- macOS full screen API와 현재 Space 전환 정책에 의존한다.

## Observability / Analytics

- `fmw.full_screen_enter_requested`, `fmw.full_screen_entered`, `fmw.full_screen_enter_failed` 이벤트를 기록한다.

## Related Interactions

- [FMW-001-adjust_file_manager_window_size](FMW-001-adjust_file_manager_window_size.md)
- [FMW-001-close_file_manager_window](FMW-001-close_file_manager_window.md)
- [FMW-001-exit_full_screen_for_file_manager_window](FMW-001-exit_full_screen_for_file_manager_window.md)
- [FMW-001-keep_file_manager_window_on_top](FMW-001-keep_file_manager_window_on_top.md)
- [FMW-001-minimize_file_manager_window](FMW-001-minimize_file_manager_window.md)
- [FMW-001-open_new_file_manager_window](FMW-001-open_new_file_manager_window.md)
- [FMW-001-quit_voyager](FMW-001-quit_voyager.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:5`
- Flows: [file_manager_window_control_flow.md](../flows/file_manager_window_control_flow.md)
- Contract: [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)
