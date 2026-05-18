---
interaction_id: "EVM-002-sort_entrires_by_property"
interaction_type: "command"
feature: "Configure Entries View"
category_key: "EVM"
feature_id: "EVM-002"
status: "배포 완료"
summary: "Entries View에서 선택한 Property를 기준으로 Entries 표시 순서를 정렬함"
related_region: "file_manager_window.content_pane"
menu: "view_menu"
shortcut: "-"
---

# Sort Entrires by Property

## Intent

- 현재 Page의 Entries View 표시 방식, 정렬, 그룹, selection 정보를 조정한다.

## Trigger / Entry Points

- `view_menu` 메뉴의 Sort Entrires by Property 항목
- file_manager_window.content_pane 영역에서 관련 컨트롤 또는 명령을 실행한 경우

## Preconditions

- 대상 Entries View이 현재 File Manager Window에서 접근 가능한 상태다.

## Expected Outcome

- Entries View에서 선택한 Property를 기준으로 Entries 표시 순서를 정렬함.
- 사용자에게 보이는 결과는 `sort_entrires_by_property_applied` 상태로 정리된다.

## State Changes

- Entries View의 표시 또는 실행 상태를 갱신한다.
- 이 인터랙션은 [evm_contract.toml](../contracts/evm_contract.toml)의 `sort_entrires_by_property_applied` 상태 어휘를 따른다.

## User-visible Feedback

- 성공 시 현재 화면의 표시, 선택, 정렬, 실행 결과가 즉시 갱신된다.
- 실패 시 기존 상태를 보존하고 실패 사유를 사용자에게 표시한다.

## Edge Cases / Failure Handling

- 대상 Entries View이 사라졌거나 권한이 없으면 작업을 중단한다.
- 동일 요청이 반복되면 마지막으로 확정된 상태를 기준으로 중복 반영을 피한다.

## Acceptance Criteria

- [ ] 대상 Entries View이 현재 File Manager Window에서 접근 가능한 상태다. 사용자가 Sort Entrires by Property을 실행하면, Entries View에서 선택한 Property를 기준으로 Entries 표시 순서를 정렬함 결과가 `sort_entrires_by_property_applied` 상태로 반영되어야 한다.
- [ ] 작업을 완료할 수 없는 조건이면, 앱은 기존 상태를 보존하고 실패 피드백을 표시해야 한다.
- [ ] 같은 interaction이 반복 호출되어도 중복되거나 모순된 상태가 남지 않아야 한다.

## Permissions / Dependencies

- 현재 Page, selection, 파일 시스템 접근 권한, File Manager Window layout 상태에 의존한다.

## Observability / Analytics

- `evm.sort_entrires_by_property` 이벤트에 성공 여부와 대상 수, 실패 사유를 기록한다.

## Related Interactions

- [EVM-002-customize_list_view_column](EVM-002-customize_list_view_column.md)
- [EVM-002-group_entries_by_property](EVM-002-group_entries_by_property.md)
- [EVM-002-set_entries_view_as_column](EVM-002-set_entries_view_as_column.md)
- [EVM-002-set_entries_view_as_graph](EVM-002-set_entries_view_as_graph.md)
- [EVM-002-set_entries_view_as_icon_grid](EVM-002-set_entries_view_as_icon_grid.md)
- [EVM-002-set_entries_view_as_list_table](EVM-002-set_entries_view_as_list_table.md)
- [EVM-002-show_hide_hidden_entry](EVM-002-show_hide_hidden_entry.md)
- [EVM-002-show_selected_entry_counts](EVM-002-show_selected_entry_counts.md)
- [EVM-002-update_entry_selection](EVM-002-update_entry_selection.md)
- [EVM-002-view_entry_counts_in_current_page](EVM-002-view_entry_counts_in_current_page.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:29`
- Flows: [evm_flow.md](../flows/evm_flow.md)
- Contract: [evm_contract.toml](../contracts/evm_contract.toml)
