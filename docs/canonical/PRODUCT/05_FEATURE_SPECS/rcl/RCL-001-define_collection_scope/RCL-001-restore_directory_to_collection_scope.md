---
interaction_id: "RCL-001-restore_directory_to_collection_scope"
interaction_type: "command"
feature: "Define Collection Scope"
category_key: "RCL"
feature_id: "RCL-001"
status: "기획 완료"
summary: "예외로 제외된 하위 경로를 다시 포함 상태로 복원해 현재 스코프 의미를 조정"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Restore Directory To Collection Scope

## Intent

- 사용자가 예외로 제외한 하위 경로를 다시 포함 상태로 복원할 수 있게 한다.
- 예외 복원으로 현재 스코프 의미를 더 넓히거나 원래 범위에 가깝게 되돌릴 수 있게 한다.
- 이 문서는 `exception_present`(예외 포함 상태) 상태를 `single_explicit_scope`(단일 명시적 스코프) 또는 `multi_explicit_scope`(다중 명시적 스코프) 쪽으로 되돌리는 restore 경로를 다룬다.

## Trigger / Entry Points

- 현재 예외 목록에서 특정 항목을 복원할 때
- 현재 범위 표시 안에서 제외된 항목을 다시 포함하려고 할 때

## Preconditions

- Collection Filter Composer가 열린 상태
- 스코프 편집창이 열린 상태
- 복원 가능한 예외가 존재하는 상태
- Generate Filter Changes from Query가 실행 중이지 않은 상태

## Expected Outcome

- 선택한 예외 항목이 제거된다.
- 기준 범위는 유지되고 현재 범위 의미만 더 넓어진다.
- 마지막 예외가 사라지면 `exception_present`(예외 포함 상태)가 아닌 상태로 돌아가야 한다.

## State Changes

- 예외 목록이 갱신된다.
- 마지막 예외가 복원되면 현재 범위는 예외 없는 상태로 돌아간다.
- 현재 범위 요약과 예외 표시가 새 상태에 맞게 갱신된다.
- 복원 후에는 변경 피드백(`change_feedback_visible`)과 되돌리기 가능(`undo_available`) 상태가 함께 갱신될 수 있다.
- 마지막 예외가 사라지면 `exception_present` 상태는 끝나야 한다.
- 복원 후 현재 스코프는 `single_explicit_scope` 또는 `multi_explicit_scope` 상태로 남고, 필요 시 `change_feedback_visible`과 `undo_available`를 함께 갱신할 수 있다.

## User-visible Feedback

- 사용자는 어떤 예외가 복원되었는지 이해할 수 있어야 한다.
- 예외가 사라진 뒤 현재 범위가 더 넓어졌다는 의미를 읽을 수 있어야 한다.

## Edge Cases / Failure Handling

- 복원할 예외가 없는 상태에서는 복원 흐름이 허용되지 않아야 한다.
- 마지막 예외를 복원하는 경우에는 예외 목록이 사라진 상태가 자연스럽게 읽혀야 한다.
- 이미 복원된 항목을 다시 복원하려는 경우에는 현재 상태를 유지해야 한다.

## Acceptance Criteria

- [ ] 예외가 존재하는 상황에서, 사용자가 특정 예외를 복원하면, 시스템은 기준 범위는 유지한 채 해당 예외만 제거해야 한다.
- [ ] 마지막 예외를 복원하는 상황에서, 시스템은 예외 없는 상태로 자연스럽게 전환되어야 한다.
- [ ] 복원할 예외가 없는 상황에서는, 시스템이 이를 허용하지 않거나 명확히 막아야 한다.

## Permissions / Dependencies

- `RCL-001-show_collection_scope_exceptions`
- `RCL-001-show_collection_scope_change_feedback`
- Contract: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flow: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)

## Observability / Analytics

- 예외 복원 시도
- 예외 복원 성공

## Related Interactions

- [RCL-001-add_directory_to_collection_scope](RCL-001-add_directory_to_collection_scope.md)
- [RCL-001-collapse_collection_filter_composer](RCL-001-collapse_collection_filter_composer.md)
- [RCL-001-exclude_directory_from_collection_scope](RCL-001-exclude_directory_from_collection_scope.md)
- [RCL-001-open_collection_filter_composer](RCL-001-open_collection_filter_composer.md)
- [RCL-001-open_collection_scope_menu](RCL-001-open_collection_scope_menu.md)
- [RCL-001-redo_collection_filter_changes](RCL-001-redo_collection_filter_changes.md)
- [RCL-001-remove_directory_from_collection_scope](RCL-001-remove_directory_from_collection_scope.md)
- [RCL-001-search_collection_scope_candidates](RCL-001-search_collection_scope_candidates.md)
- [RCL-001-show_collection_scope_candidate_disambiguation](RCL-001-show_collection_scope_candidate_disambiguation.md)
- [RCL-001-show_collection_scope_change_feedback](RCL-001-show_collection_scope_change_feedback.md)
- [RCL-001-show_collection_scope_exceptions](RCL-001-show_collection_scope_exceptions.md)
- [RCL-001-show_collection_scope_summary](RCL-001-show_collection_scope_summary.md)
- [RCL-001-toggle_collection_scope_subfolder_inclusion](RCL-001-toggle_collection_scope_subfolder_inclusion.md)
- [RCL-001-undo_collection_filter_changes](RCL-001-undo_collection_filter_changes.md)
## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:126`
- Contracts: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flows: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)
