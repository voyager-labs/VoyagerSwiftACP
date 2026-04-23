---
interaction_id: "RCL-001-exclude_directory_from_collection_scope"
interaction_type: "command"
feature: "Define Collection Scope"
category_key: "RCL"
feature_id: "RCL-001"
status: "기획 완료"
summary: "현재 기준 범위 안의 특정 하위 경로를 예외로 제외해 전체 범위를 다시 고르지 않고도 범위를 좁힘"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Exclude Directory From Collection Scope

## Intent

- 사용자가 현재 기준 범위를 유지한 채 특정 하위 경로만 예외로 제외할 수 있게 한다.
- 전체 범위를 다시 고르는 것보다 더 가볍게 현재 범위를 조정할 수 있게 한다.
- 이 문서는 `single_explicit_scope`(단일 명시적 스코프) 또는 `multi_explicit_scope`(다중 명시적 스코프)에서 `exception_present`(예외 포함 상태) 상태를 만드는 경로를 다룬다.

## Trigger / Entry Points

- 스코프 편집창에서 현재 기준 범위 아래의 하위 경로를 예외로 지정할 때
- 현재 범위 표시 안에서 특정 하위 경로를 제외하는 흐름으로 진입할 때

## Preconditions

- Collection Filter Composer가 열린 상태
- 스코프 편집창이 열린 상태
- 적어도 하나의 기준 범위가 존재하는 상태
- Generate Filter Changes from Query가 실행 중이지 않은 상태

## Expected Outcome

- 선택한 하위 경로가 예외로 추가된다.
- 기준 범위는 유지되고, 현재 범위 의미만 더 좁아진다.
- 예외가 추가되면 현재 스코프는 `exception_present` 상태로 읽혀야 한다.

## State Changes

- 예외 목록이 갱신된다.
- 현재 범위 요약과 예외 표시가 새 상태에 맞게 갱신된다.
- 예외 추가 후에는 변경 피드백(`change_feedback_visible`)과 되돌리기 가능(`undo_available`) 상태가 함께 갱신될 수 있다.
- 예외 추가가 성공하면 현재 스코프는 `exception_present` 상태로 유지되어야 한다.
- 예외 추가 후 현재 스코프는 `single_explicit_scope` 또는 `multi_explicit_scope`를 유지하면서 `exception_present` 상태를 함께 가져야 한다.

## User-visible Feedback

- 사용자는 어떤 하위 경로가 현재 범위에서 제외되었는지 이해할 수 있어야 한다.
- 예외 추가는 기준 범위 제거와 다른 동작으로 읽혀야 한다.

## Edge Cases / Failure Handling

- 이미 예외로 제외된 경로를 다시 제외하려는 경우에는 중복 추가 없이 현재 상태를 유지한다.
- 현재 기준 범위 밖의 경로는 예외 대상으로 다룰 수 없어야 한다.
- 기준 범위가 없는 상태에서는 예외 추가 흐름이 허용되지 않아야 한다.

## Acceptance Criteria

- [ ] 기준 범위가 존재하는 상황에서, 사용자가 그 하위 경로를 예외로 제외하면, 시스템은 기준 범위는 유지한 채 예외 목록에 해당 경로를 추가해야 한다.
- [ ] 이미 예외로 제외된 경로를 다시 제외하려는 상황에서, 시스템은 중복 추가 없이 현재 상태를 유지해야 한다.
- [ ] 기준 범위 밖의 경로를 예외로 다루려는 상황에서는, 시스템이 이를 허용하지 않거나 명확히 막아야 한다.

## Permissions / Dependencies

- `RCL-001-show_collection_scope_exceptions`
- `RCL-001-show_collection_scope_change_feedback`
- Contract: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flow: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)

## Observability / Analytics

- 예외 추가 시도
- 예외 추가 성공

## Related Interactions

- [RCL-001-add_directory_to_collection_scope](RCL-001-add_directory_to_collection_scope.md)
- [RCL-001-collapse_collection_filter_composer](RCL-001-collapse_collection_filter_composer.md)
- [RCL-001-open_collection_filter_composer](RCL-001-open_collection_filter_composer.md)
- [RCL-001-open_collection_scope_menu](RCL-001-open_collection_scope_menu.md)
- [RCL-001-redo_collection_filter_changes](RCL-001-redo_collection_filter_changes.md)
- [RCL-001-remove_directory_from_collection_scope](RCL-001-remove_directory_from_collection_scope.md)
- [RCL-001-restore_directory_to_collection_scope](RCL-001-restore_directory_to_collection_scope.md)
- [RCL-001-search_collection_scope_candidates](RCL-001-search_collection_scope_candidates.md)
- [RCL-001-show_collection_scope_candidate_disambiguation](RCL-001-show_collection_scope_candidate_disambiguation.md)
- [RCL-001-show_collection_scope_change_feedback](RCL-001-show_collection_scope_change_feedback.md)
- [RCL-001-show_collection_scope_exceptions](RCL-001-show_collection_scope_exceptions.md)
- [RCL-001-show_collection_scope_summary](RCL-001-show_collection_scope_summary.md)
- [RCL-001-toggle_collection_scope_subfolder_inclusion](RCL-001-toggle_collection_scope_subfolder_inclusion.md)
- [RCL-001-undo_collection_filter_changes](RCL-001-undo_collection_filter_changes.md)
## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:125`
- Contracts: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flows: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)
