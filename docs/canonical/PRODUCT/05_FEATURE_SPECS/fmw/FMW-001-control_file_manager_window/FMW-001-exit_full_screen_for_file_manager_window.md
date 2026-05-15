---
interaction_id: "FMW-001-exit_full_screen_for_file_manager_window"
interaction_type: "command"
feature: "Control File Manager Window"
category_key: "FMW"
feature_id: "FMW-001"
status: "배포 완료"
summary: "전체 화면 모드의 해당 File Manager 창을 원래 창 크기로 되돌림"
related_region: "file_manager_window"
menu: "view_menu"
shortcut: "⌘⌃F; ESC"
---

# Exit Full Screen for File Manager Window

## Intent

- 전체 화면 상태의 File Manager Window를 일반 창으로 되돌린다.

## Trigger / Entry Points

- `view_menu`의 Exit Full Screen 항목
- `⌘⌃F` 단축키
- `ESC` 키 또는 macOS 전체 화면 해제 컨트롤

## Preconditions

- 대상 File Manager Window가 `full_screen` 상태다.

## Expected Outcome

- 대상 창은 전체 화면 Space를 벗어나 `windowed` 상태로 돌아온다.

## State Changes

- 창 표시 모드만 변경하며 창 내부 페이지와 패인 상태는 보존한다.
- 이 인터랙션은 [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)의 `windowed` 상태 어휘를 따른다.

## User-visible Feedback

- OS 전체 화면 해제 애니메이션이 표시된다.
- 해제가 실패하면 `full_screen` 상태를 유지하고 실패 사유를 표시한다.

## Edge Cases / Failure Handling

- 이미 일반 창이면 새 해제 동작을 만들지 않는다.
- 외부 디스플레이 변경 중이면 OS 전환 완료 후 최종 창 프레임을 보정한다.

## Acceptance Criteria

- [ ] 창이 `full_screen` 상태일 때 사용자가 Exit Full Screen을 실행하면, 대상 창은 `windowed` 상태가 되어야 한다.
- [ ] 전체 화면 해제 후에도 페이지, 선택, Sidebar, Inspector Pane 상태는 보존되어야 한다.
- [ ] 이미 `windowed` 상태에서 호출되면, 앱은 불필요한 상태 변경을 만들지 않아야 한다.

## Permissions / Dependencies

- macOS full screen 해제 API와 창 프레임 복원 값에 의존한다.

## Observability / Analytics

- `fmw.full_screen_exit_requested`, `fmw.windowed_restored`, `fmw.full_screen_exit_failed` 이벤트를 기록한다.

## Related Interactions

- [FMW-001-adjust_file_manager_window_size](FMW-001-adjust_file_manager_window_size.md)
- [FMW-001-close_file_manager_window](FMW-001-close_file_manager_window.md)
- [FMW-001-enter_full_screen_for_file_manager_window](FMW-001-enter_full_screen_for_file_manager_window.md)
- [FMW-001-keep_file_manager_window_on_top](FMW-001-keep_file_manager_window_on_top.md)
- [FMW-001-minimize_file_manager_window](FMW-001-minimize_file_manager_window.md)
- [FMW-001-open_new_file_manager_window](FMW-001-open_new_file_manager_window.md)
- [FMW-001-quit_voyager](FMW-001-quit_voyager.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:6`
- Flows: [file_manager_window_control_flow.md](../flows/file_manager_window_control_flow.md)
- Contract: [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)
