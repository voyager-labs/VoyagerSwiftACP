---
interaction_id: "RCL-001-toggle_collection_scope_subfolder_inclusion"
interaction_type: "input"
feature: "Define Collection Scope"
category_key: "RCL"
feature_id: "RCL-001"
status: "기획 완료"
summary: "하위 폴더 자동 포함 규칙을 켜거나 꺼 현재 스코프가 어떤 범위까지 포함하는지 조정"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Toggle Collection Scope Subfolder Inclusion

## Intent

- 사용자가 선택한 범위의 하위 폴더가 기본적으로 함께 포함되는지 이해하고 조정할 수 있게 한다.
- 현재 스코프 의미와 실제 포함 범위 해석이 어긋나지 않게 한다.
- 이 문서는 `single_explicit_scope`(단일 명시적 스코프), `multi_explicit_scope`(다중 명시적 스코프), `exception_present`(예외 포함 상태) 상태에서 include-subfolders 해석을 조정하는 경로를 다룬다.

## Trigger / Entry Points

- 스코프 편집창 안에서 하위 폴더 포함 규칙을 켜거나 끌 때
- 현재 범위 의미를 더 넓게 또는 더 좁게 조정하려고 할 때

## Preconditions

- Collection Filter Composer가 열린 상태
- 스코프 편집창이 열린 상태
- 스코프 의미를 해석할 수 있는 기준 범위가 존재하는 상태

## Expected Outcome

- 하위 폴더 자동 포함 규칙의 현재 상태를 읽을 수 있다.
- 규칙이 켜져 있으면 기준 범위 아래 하위 폴더는 기본 포함으로 해석되어야 한다.
- 규칙이 꺼져 있으면 기준 범위 자체만 포함되고 하위 폴더는 기본 포함으로 해석되면 안 된다.
- 사용자가 규칙을 바꾸면 현재 스코프 의미도 그에 맞게 즉시 다시 해석되어야 한다.
- 이 동작은 `single_explicit_scope`, `multi_explicit_scope`, `exception_present` 상태 모두에서 같은 규칙으로 적용되어야 한다.
- 규칙 변경은 `single_explicit_scope`, `multi_explicit_scope`, `exception_present` 상태를 해석하는 방식에 직접 영향을 준다.

## State Changes

- 하위 폴더 자동 포함 규칙 상태가 갱신된다.
- 현재 범위 요약과 예외 해석이 새 규칙에 맞게 갱신된다.
- 규칙이 켜짐에서 꺼짐으로 바뀌면 하위 폴더의 기본 포함 의미가 제거된다.
- 규칙이 꺼짐에서 켜짐으로 바뀌면 하위 폴더의 기본 포함 의미가 다시 추가된다.
- 규칙 변경 후에는 변경 피드백(`change_feedback_visible`)과 되돌리기 가능(`undo_available`) 상태가 함께 갱신될 수 있다.
- 규칙 변경 뒤 `exception_present` 상태가 있었다면 그 표시도 같은 해석 규칙에 맞게 유지되어야 한다.
- 규칙 변경 뒤에는 `change_feedback_visible`과 `undo_available` 상태가 함께 갱신되고, 기존 예외가 있으면 계속 `exception_present` 상태로 읽혀야 한다.

## User-visible Feedback

- 사용자는 현재 규칙이 켜져 있는지 꺼져 있는지 분명히 이해할 수 있어야 한다.
- 규칙이 켜져 있어도 모든 하위 폴더가 현재 직접 선택된 것처럼 읽히면 안 된다.
- 일부 하위 폴더가 예외로 제외된 상태에서도 현재 규칙이 함께 이해되어야 한다.
- 규칙이 꺼져 있을 때는 하위 폴더가 기본 포함되는 것처럼 읽히면 안 된다.
- 규칙 상태가 바뀌면 현재 범위 요약과 예외 표시는 같은 상태 전환을 기준으로 갱신되어야 한다.

## Edge Cases / Failure Handling

- 예외가 존재하는 상황에서도 규칙과 예외가 서로 모순되게 읽히지 않아야 한다.
- 다중 기준 범위 상태에서도 하나의 일관된 해석 기준이 유지되어야 한다.
- 현재 규칙을 바꿨을 때 범위 의미가 크게 바뀌더라도 사용자가 이를 이해할 수 있어야 한다.

## Acceptance Criteria

- [ ] 사용자가 특정 범위를 선택한 상태에서 하위 폴더 자동 포함 규칙을 켜면, 시스템은 그 범위의 하위 폴더가 기본적으로 함께 포함된다는 의미를 읽을 수 있게 해야 한다.
- [ ] 예외가 존재하는 상황에서, 사용자가 현재 스코프를 보면, 시스템은 자동 포함 규칙과 예외 규칙을 함께 일관되게 읽히게 해야 한다.
- [ ] 사용자가 자동 포함 규칙을 끄거나 켜면, 시스템은 현재 범위 의미가 바뀌었음을 요약과 표시에서 이해할 수 있게 해야 한다.
- [ ] 규칙이 꺼져 있는 상황에서, 시스템은 하위 폴더가 기본 포함되는 것처럼 읽히게 하면 안 된다.
- [ ] 규칙 상태가 바뀌면, 시스템은 현재 범위 요약과 예외 표시를 같은 상태 전환에 맞춰 함께 갱신해야 한다.

## Permissions / Dependencies

- `RCL-001-show_collection_scope_summary`
- `RCL-001-show_collection_scope_exceptions`
- `RCL-001-show_collection_scope_change_feedback`
- Contract: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flow: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)

## Observability / Analytics

- 하위 폴더 포함 규칙 변경

## Related Interactions

- [RCL-001-add_directory_to_collection_scope](RCL-001-add_directory_to_collection_scope.md)
- [RCL-001-collapse_collection_filter_composer](RCL-001-collapse_collection_filter_composer.md)
- [RCL-001-exclude_directory_from_collection_scope](RCL-001-exclude_directory_from_collection_scope.md)
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
- [RCL-001-undo_collection_filter_changes](RCL-001-undo_collection_filter_changes.md)
## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:127`
- Contracts: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flows: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)
