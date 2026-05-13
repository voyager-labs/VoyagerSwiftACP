---
interaction_id: "FMW-001-adjust_file_manager_window_size"
interaction_type: "input"
feature: "Control File Manager Window"
category_key: "FMW"
feature_id: "FMW-001"
status: "배포 완료"
summary: "File Manager 창의 Width/Hegith를 최소-최대 범위 내에서 조정"
related_region: "file_manager_window"
menu: "-"
shortcut: "-"
---

# Adjust File Manager Window Size

## Intent

- File Manager Window의 너비와 높이를 사용 가능한 범위 안에서 조정한다.

## Trigger / Entry Points

- 사용자가 창 가장자리 또는 모서리를 드래그한 경우
- OS가 창 프레임 조정 이벤트를 전달한 경우

## Preconditions

- 대상 File Manager Window가 열려 있고 크기 조정 가능한 표시 상태다.

## Expected Outcome

- 창 프레임은 최소·최대 크기 제약 안에서 갱신되고 `window_resized` 상태가 된다.

## State Changes

- 창 크기 값을 갱신하고, 필요한 경우 Sidebar와 Inspector Pane의 표시 가능 영역을 재계산한다.
- 허용 범위를 벗어난 값은 저장하지 않고 가장 가까운 허용값으로 보정한다.
- 이 인터랙션은 [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)의 `window_resized` 상태 어휘를 따른다.

## User-visible Feedback

- 드래그 중 창 크기가 실시간으로 변경된다.
- 최소 또는 최대 한계에 도달하면 더 이상 같은 방향으로 늘어나거나 줄어들지 않는다.

## Edge Cases / Failure Handling

- 사용자가 최소 너비보다 작게 줄이려 하면 최소 너비로 clamp한다.
- 표시 중인 패인 너비 합이 창 최소 너비보다 크면 패인 우선순위에 따라 표시 영역을 보정한다.

## Acceptance Criteria

- [ ] 사용자가 창 크기를 조정하면, File Manager Window는 허용 범위 안에서만 `window_resized` 상태로 갱신되어야 한다.
- [ ] 허용 최소값보다 작게 줄이려 하면, 앱은 최소 창 크기를 유지해야 한다.
- [ ] 크기 조정 중에도 현재 페이지와 선택 상태는 보존되어야 한다.

## Permissions / Dependencies

- macOS window frame constraints와 FMW layout minimum size 정책에 의존한다.

## Observability / Analytics

- `fmw.window_resized` 이벤트에 최종 width, height, clamp 여부를 기록한다.

## Related Interactions

- [FMW-001-close_file_manager_window](FMW-001-close_file_manager_window.md)
- [FMW-001-enter_full_screen_for_file_manager_window](FMW-001-enter_full_screen_for_file_manager_window.md)
- [FMW-001-exit_full_screen_for_file_manager_window](FMW-001-exit_full_screen_for_file_manager_window.md)
- [FMW-001-keep_file_manager_window_on_top](FMW-001-keep_file_manager_window_on_top.md)
- [FMW-001-minimize_file_manager_window](FMW-001-minimize_file_manager_window.md)
- [FMW-001-open_new_file_manager_window](FMW-001-open_new_file_manager_window.md)
- [FMW-001-quit_voyager](FMW-001-quit_voyager.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:9`
- Flows: [file_manager_window_control_flow.md](../flows/file_manager_window_control_flow.md)
- Contract: [file_manager_window_contract.toml](../contracts/file_manager_window_contract.toml)
