---
interaction_id: "FMW-001-close_file_manager_window"
interaction_type: "command"
feature: "Control File Manager Window"
category_key: "FMW"
feature_id: "FMW-001"
status: "배포 완료"
summary: "해당 File Manager 창을 닫음"
related_region: "file_manager_window"
menu: "file_menu"
shortcut: "⌘⇧W"
---

# Close File Manager Window

## Intent

- 활성 File Manager Window 하나를 닫아 해당 창의 작업 세션을 종료한다.

## Trigger / Entry Points

- `file_menu`의 Close Window 항목
- `⌘⇧W` 단축키
- 창 닫기 버튼

## Preconditions

- 닫을 File Manager Window가 활성 상태이며 닫기 요청을 받을 수 있다.

## Expected Outcome

- 대상 창은 `window_closing`을 거쳐 `window_closed` 상태가 된다.
- 다른 File Manager Window와 앱 전체 실행 상태는 유지된다.

## State Changes

- 대상 창에 연결된 페이지, 선택, 패인 표시 상태를 창 세션과 함께 정리한다.
- 저장되지 않은 변경이나 취소 불가능한 작업이 있으면 닫기 상태 전환을 보류한다.
- 이 인터랙션은 [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)의 `window_closing`, `window_closed` 상태 어휘를 따른다.

## User-visible Feedback

- 즉시 닫을 수 있으면 별도 성공 메시지 없이 창이 사라진다.
- 확인이 필요하면 닫기 확인 대화 또는 차단 사유를 표시한다.

## Edge Cases / Failure Handling

- 창에서 진행 중인 작업이 있으면 닫기 전에 취소·보존 가능 여부를 확인한다.
- 같은 창에 닫기 요청이 중복으로 들어오면 기존 `window_closing` 흐름만 유지한다.

## Acceptance Criteria

- [ ] 활성 File Manager Window에 저장되지 않은 변경이 없을 때 사용자가 Close Window를 실행하면, 대상 창은 `window_closed` 상태가 되어야 한다.
- [ ] 닫기 전 확인이 필요한 작업이 있으면, 앱은 창을 즉시 닫지 않고 확인 대화를 표시해야 한다.
- [ ] 닫기 처리 중 같은 창에 Close Window가 다시 호출되면, 중복 정리를 실행하지 않아야 한다.

## Permissions / Dependencies

- 창 세션 정리, 진행 중 작업 취소 정책, macOS window close 이벤트에 의존한다.

## Observability / Analytics

- `fmw.window_close_requested`, `fmw.window_closed`, `fmw.window_close_blocked` 이벤트를 기록한다.

## Related Interactions

- [FMW-001-adjust_file_manager_window_size](FMW-001-adjust_file_manager_window_size.md)
- [FMW-001-enter_full_screen_for_file_manager_window](FMW-001-enter_full_screen_for_file_manager_window.md)
- [FMW-001-exit_full_screen_for_file_manager_window](FMW-001-exit_full_screen_for_file_manager_window.md)
- [FMW-001-keep_file_manager_window_on_top](FMW-001-keep_file_manager_window_on_top.md)
- [FMW-001-minimize_file_manager_window](FMW-001-minimize_file_manager_window.md)
- [FMW-001-open_new_file_manager_window](FMW-001-open_new_file_manager_window.md)
- [FMW-001-quit_voyager](FMW-001-quit_voyager.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:4`
- Flows: [file_manager_window_control_flow.md](../flows/file_manager_window_control_flow.md)
- Contract: [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)
