---
interaction_id: "FMW-001-open_new_file_manager_window"
interaction_type: "command"
feature: "Control File Manager Window"
category_key: "FMW"
feature_id: "FMW-001"
status: "배포 완료"
summary: "현재 사용 중인 데스크탑에서 새 File Manager 창을 생성해 새로운 세션을 시작"
related_region: "file_manager_window"
menu: "file_menu"
shortcut: "⌘N"
---

# Open New File Manager Window

## Intent

- 현재 데스크탑에서 새 File Manager Window를 열어 독립적인 작업 세션을 시작한다.

## Trigger / Entry Points

- `file_menu`의 New Window 항목
- `⌘N` 단축키
- Dock 또는 시스템 수준에서 새 창 요청이 전달된 경우

## Preconditions

- Voyager 앱이 실행 중이며 새 창을 만들 수 있는 리소스가 남아 있다.

## Expected Outcome

- 새 File Manager Window가 생성되고 활성 창으로 전환된다.
- 새 창은 `window_open` 상태로 시작하며 기본 Sidebar와 Content Pane 구성을 가진다.

## State Changes

- 새 File Manager Window 창 세션을 생성한다.
- 기존 File Manager Window의 페이지, 선택, 패인 상태는 변경하지 않는다.
- 이 인터랙션은 [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)의 `window_open` 상태 어휘를 따른다.

## User-visible Feedback

- 성공 시 새 창이 전면에 표시된다.
- 리소스 부족으로 실패하면 새 창을 만들지 않고 실패 사유를 표시한다.

## Edge Cases / Failure Handling

- 시스템 메모리 또는 창 생성 권한이 부족하면 생성 요청을 실패 처리한다.
- 다중 모니터 환경에서는 OS가 결정한 활성 Space에 새 창을 표시한다.

## Acceptance Criteria

- [ ] 앱이 활성 상태일 때 사용자가 New Window를 실행하면, 새 File Manager Window가 생성되고 `window_open` 상태로 활성화되어야 한다.
- [ ] 새 창 생성이 실패하면, 기존 창 상태를 변경하지 않고 실패 피드백을 표시해야 한다.
- [ ] 여러 창이 이미 열려 있어도 새 창 생성은 기존 창의 페이지와 선택 상태를 보존해야 한다.

## Permissions / Dependencies

- macOS window scene 생성과 초기 File Manager layout 설정에 의존한다.

## Observability / Analytics

- `fmw.window_open_requested`, `fmw.window_opened`, `fmw.window_open_failed` 이벤트를 기록한다.

## Related Interactions

- [FMW-001-adjust_file_manager_window_size](FMW-001-adjust_file_manager_window_size.md)
- [FMW-001-close_file_manager_window](FMW-001-close_file_manager_window.md)
- [FMW-001-enter_full_screen_for_file_manager_window](FMW-001-enter_full_screen_for_file_manager_window.md)
- [FMW-001-exit_full_screen_for_file_manager_window](FMW-001-exit_full_screen_for_file_manager_window.md)
- [FMW-001-keep_file_manager_window_on_top](FMW-001-keep_file_manager_window_on_top.md)
- [FMW-001-minimize_file_manager_window](FMW-001-minimize_file_manager_window.md)
- [FMW-001-quit_voyager](FMW-001-quit_voyager.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:3`
- Flows: [file_manager_window_control_flow.md](../flows/file_manager_window_control_flow.md)
- Contract: [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)
