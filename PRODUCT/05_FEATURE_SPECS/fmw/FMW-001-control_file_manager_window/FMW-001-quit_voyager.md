---
interaction_id: "FMW-001-quit_voyager"
interaction_type: "command"
feature: "Control File Manager Window"
category_key: "FMW"
feature_id: "FMW-001"
status: "배포 완료"
summary: "앱을 종료"
related_region: "file_manager_window"
menu: "voyager_menu"
shortcut: "⌘Q"
---

# Quit Voyager

## Intent

- Voyager 앱 전체를 명시적으로 종료해 열려 있는 모든 File Manager Window와 백그라운드 세션을 정리한다.

## Trigger / Entry Points

- `voyager_menu`의 Quit Voyager 항목
- `⌘Q` 단축키
- macOS 앱 종료 이벤트가 Voyager로 전달된 경우

## Preconditions

- Voyager가 실행 중이고 하나 이상의 File Manager Window 또는 백그라운드 작업 컨텍스트가 존재한다.

## Expected Outcome

- 종료가 허용되면 사용자에게 보이는 앱 상태는 `app_terminating`이 되고 모든 File Manager Window가 닫힌다.
- 종료 전 확인이 필요한 작업이 있으면 종료를 보류하고 확인 또는 차단 피드백을 먼저 표시한다.

## State Changes

- 모든 File Manager Window의 창 세션을 닫기 대상으로 표시한다.
- 진행 중인 종료 요청은 중복 실행하지 않고 기존 `app_terminating` 흐름에 합류한다.
- 이 인터랙션은 [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)의 `app_terminating` 상태 어휘를 따른다.

## User-visible Feedback

- 확인 없이 종료 가능한 경우 별도 성공 메시지 없이 앱이 종료된다.
- 저장되지 않은 변경이나 진행 중 작업이 있으면 종료 전 확인 대화 또는 차단 사유를 표시한다.

## Edge Cases / Failure Handling

- 진행 중인 인덱싱·복사·대화 요청이 있으면 취소 가능 여부를 확인하고 종료 정책에 맞게 정리한다.
- 이미 종료 처리 중이면 새 종료 요청을 무시하고 기존 종료 흐름을 유지한다.

## Acceptance Criteria

- [ ] Voyager가 활성 상태일 때 사용자가 Quit Voyager를 실행하면, 종료 가능한 모든 File Manager Window가 닫히고 앱 상태가 `app_terminating`으로 전환되어야 한다.
- [ ] 종료 전 확인이 필요한 작업이 있을 때 사용자가 Quit Voyager를 실행하면, 앱은 즉시 종료하지 않고 확인 또는 차단 피드백을 표시해야 한다.
- [ ] 이미 종료 처리 중일 때 Quit Voyager가 다시 호출되면, 중복 종료 처리를 만들지 않고 기존 종료 흐름을 유지해야 한다.

## Permissions / Dependencies

- macOS application lifecycle 이벤트와 창 세션 정리 정책에 의존한다.

## Observability / Analytics

- `fmw.quit_requested`, `fmw.quit_blocked`, `fmw.quit_confirmed` 이벤트를 기록한다.

## Related Interactions

- [FMW-001-adjust_file_manager_window_size](FMW-001-adjust_file_manager_window_size.md)
- [FMW-001-close_file_manager_window](FMW-001-close_file_manager_window.md)
- [FMW-001-enter_full_screen_for_file_manager_window](FMW-001-enter_full_screen_for_file_manager_window.md)
- [FMW-001-exit_full_screen_for_file_manager_window](FMW-001-exit_full_screen_for_file_manager_window.md)
- [FMW-001-keep_file_manager_window_on_top](FMW-001-keep_file_manager_window_on_top.md)
- [FMW-001-minimize_file_manager_window](FMW-001-minimize_file_manager_window.md)
- [FMW-001-open_new_file_manager_window](FMW-001-open_new_file_manager_window.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:2`
- Flows: [file_manager_window_control_flow.md](../flows/file_manager_window_control_flow.md)
- Contract: [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)
