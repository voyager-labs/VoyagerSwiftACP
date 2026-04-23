---
interaction_id: "RCL-001-remove_directory_from_collection_scope"
interaction_type: "command"
feature: "Define Collection Scope"
category_key: "RCL"
feature_id: "RCL-001"
status: "배포 완료"
summary: "스코프 편집창에서 명시적 범위를 제거해 현재 콜렉션의 기준 범위를 단순화하거나 root-only 상태로 복귀"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Remove Directory From Collection Scope

## Intent

- 사용자가 현재 명시적 스코프에 포함된 기준 범위 중 하나를 제거해 콜렉션 범위를 단순화하거나 기본 상태로 되돌린다.
- 이 문서는 `single_explicit_scope`, `multi_explicit_scope`, `exception_present` 상태에서 기준 범위를 제거하는 경로를 다룬다.

## Trigger / Entry Points

- 스코프 편집창에서 현재 포함된 기준 범위 항목을 제거

## Preconditions

- Collection Filter Composer가 열린 상태
- 스코프 편집창이 열린 상태
- Generate Filter Changes from Query가 실행 중이지 않은 상태

## Expected Outcome

- 선택한 명시적 스코프가 제거된다.
- 마지막 명시적 스코프가 제거되면 현재 범위는 root-only 상태로 복귀한다.
- 이 동작은 `multi_explicit_scope`(다중 명시적 스코프)에서 `single_explicit_scope`(단일 명시적 스코프)로, 필요 시 `single_explicit_scope`(단일 명시적 스코프)에서 `root_only`로 전환되는 흐름이다.
- 예외가 남아 있으면 현재 스코프는 여전히 `exception_present`(예외 포함 상태) 상태일 수 있다.

## State Changes

- 명시적 스코프 목록이 갱신된다.
- 남은 명시적 스코프가 없으면 root-only 상태가 된다.
- 현재 범위 요약이 현재 상태에 맞게 갱신된다.
- 제거된 기준 범위 안에서만 의미가 있던 예외는 현재 스코프에서 제거되어야 한다.
- 다른 남은 기준 범위 아래에도 속하는 예외는 유지되어야 한다.
- 제거 후에는 `exception_present`(예외 포함 상태), 변경 피드백(`change_feedback_visible`), 되돌리기 가능(`undo_available`) 상태가 함께 재계산되어야 한다.
- 마지막 제거 이후에는 필요 시 `root_only` 상태로 복귀해야 한다.
- 제거 후에는 `single_explicit_scope` / `root_only` / `exception_present` / `change_feedback_visible` / `undo_available` 상태가 함께 재계산되어야 한다.

## User-visible Feedback

- 어떤 기준 범위가 제거되었는지 이해 가능해야 한다.
- 마지막 명시적 스코프를 제거했을 때 현재 범위가 root-only 상태로 돌아갔다는 의미가 읽혀야 한다.

## Edge Cases / Failure Handling

- 마지막 명시적 스코프를 제거하는 경우
- 현재 보고 있는 의미와 연결된 범위를 제거하는 경우
- 예외 제거와 기준 범위 제거가 혼동될 수 있는 경우
- 특정 예외가 제거되는 기준 범위에만 속하는 경우

## Acceptance Criteria

- [ ] 명시적 스코프가 둘 이상인 상황에서, 사용자가 하나를 제거하면, 나머지 범위는 유지되어야 한다.
- [ ] 마지막 명시적 스코프를 제거하는 상황에서, 사용자가 해당 범위를 제거하면, 현재 콜렉션은 root-only 상태로 돌아가야 한다.
- [ ] 특정 하위 경로를 예외로 제외하는 동작은 이 인터랙션이 아니라 별도 exclusion interaction으로 다뤄져야 한다.
- [ ] 제거된 기준 범위에만 속하던 예외는 시스템이 함께 제거해야 한다.
- [ ] 다른 남은 기준 범위 아래에도 속하는 예외는 시스템이 유지해야 한다.

## Permissions / Dependencies

- 기준 범위 제거와 예외 지정이 같은 의미로 읽히지 않아야 한다.
- 현재 범위 요약이 제거 이후 상태와 정합하게 갱신되어야 한다.
- 제거 이후 예외 유지 여부는 "남은 기준 범위 중 하나 이상 아래에 속하는가"를 기준으로 판단해야 한다.
- Contract: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flow: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)

## Observability / Analytics

- 명시적 스코프 제거 시도
- remove 성공
- root-only 복귀 여부

## Related Interactions

- [RCL-001-add_directory_to_collection_scope](RCL-001-add_directory_to_collection_scope.md)
- [RCL-001-collapse_collection_filter_composer](RCL-001-collapse_collection_filter_composer.md)
- [RCL-001-exclude_directory_from_collection_scope](RCL-001-exclude_directory_from_collection_scope.md)
- [RCL-001-open_collection_filter_composer](RCL-001-open_collection_filter_composer.md)
- [RCL-001-open_collection_scope_menu](RCL-001-open_collection_scope_menu.md)
- [RCL-001-redo_collection_filter_changes](RCL-001-redo_collection_filter_changes.md)
- [RCL-001-restore_directory_to_collection_scope](RCL-001-restore_directory_to_collection_scope.md)
- [RCL-001-search_collection_scope_candidates](RCL-001-search_collection_scope_candidates.md)
- [RCL-001-show_collection_scope_candidate_disambiguation](RCL-001-show_collection_scope_candidate_disambiguation.md)
- [RCL-001-show_collection_scope_change_feedback](RCL-001-show_collection_scope_change_feedback.md)
- [RCL-001-show_collection_scope_exceptions](RCL-001-show_collection_scope_exceptions.md)
- [RCL-001-show_collection_scope_summary](RCL-001-show_collection_scope_summary.md)
- [RCL-001-toggle_collection_scope_subfolder_inclusion](RCL-001-toggle_collection_scope_subfolder_inclusion.md)
- [RCL-001-undo_collection_filter_changes](RCL-001-undo_collection_filter_changes.md)
## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:124`
- Contracts: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flows: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)
