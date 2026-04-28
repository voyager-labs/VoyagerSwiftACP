---
interaction_id: "RCL-001-redo_collection_filter_changes"
interaction_type: "command"
feature: "Define Collection Scope"
category_key: "RCL"
feature_id: "RCL-001"
status: "배포 완료"
summary: "되돌린 필터 편집 작업을 한 단계 다시 적용해 되돌리기 전으로 복원"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "⌘⇧Z"
---

# Redo Collection Filter Changes

## Intent

- 사용자가 되돌린 최근 변경을 다시 적용해 직전 undo 이전 상태로 복귀할 수 있게 한다.
- redo는 undo와 대칭인 1단계 복원 흐름으로 동작해야 한다.

## Trigger / Entry Points

- 키보드 단축키 `⌘⇧Z`
- redo 액션을 실행할 때

## Preconditions

- Generate Filter Changes from Query가 실행 중이지 않은 상태
- 필터 편집 되돌린 내역이 존재하는 상태

## Expected Outcome

- 가장 최근에 되돌린 변경 1건이 다시 적용되어야 한다.
- redo 후 현재 범위 의미와 표시가 redo 대상 상태와 일치해야 한다.
- redo는 더 오래된 다른 변경까지 함께 다시 적용하면 안 된다.
- 이 문서는 `redo_available` 상태에서만 유효한 다시 적용 흐름을 다룬다.
- redo가 끝나면 현재 변경 피드백은 다시 `change_feedback_visible` 상태를 기준으로 읽혀야 한다.

## State Changes

- 가장 최근 undo 대상 1건이 다시 적용된다.
- 현재 범위 요약, 조건 상태, 변경 피드백이 redo된 상태 기준으로 갱신된다.
- redo 가능한 항목이 더 없으면 redo 진입은 사라지거나 무효 처리되어야 한다.

## User-visible Feedback

- 사용자는 어떤 변경이 다시 적용되었는지 이해할 수 있어야 한다.
- redo 후에는 결과가 왜 다시 바뀌었는지도 읽을 수 있어야 한다.
- redo 가능한 내역이 없으면 redo를 성공한 것처럼 보이면 안 된다.
- redo를 수행할 수 있는 상황에서는 contract 용어 기준의 `다시 적용 가능` 상태가 함께 읽혀야 한다.

## Edge Cases / Failure Handling

- redo 가능한 내역이 없는 경우
- 연속 redo가 가능한 경우
- redo 적용 실패가 발생하는 경우
- 조건 변경과 스코프 변경 redo가 섞이는 경우

## Acceptance Criteria

- [ ] 필터 편집을 되돌린 내역이 존재하는 상태일 때, 사용자가 해당 인터랙션을 호출하면, 되돌린 필터
      편집을 다시 적용하여 필터 상태를 갱신함
- [ ] redo 가능한 내역이 없는 상황에서는, 시스템이 redo를 성공한 것처럼 보이면 안 되며 현재 redo 불가 상태를 명확히 보여줘야 한다.
- [ ] redo가 스코프 변경을 다시 적용하는 상황에서는, 시스템은 현재 범위 의미와 결과 해석을 redo 대상 상태로 함께 복원해야 한다.
- [ ] 연속 redo가 가능한 상황에서는, 시스템은 한 번에 가장 최근 undo 대상 1건만 다시 적용해야 한다.

## Permissions / Dependencies

- `RCL-001-undo_collection_filter_changes`
- Contract: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flow: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)

## Observability / Analytics

- redo 호출
- redo 대상 변경 유형
- redo 성공 / 실패

## Related Interactions

- [RCL-001-add_directory_to_collection_scope](RCL-001-add_directory_to_collection_scope.md)
- [RCL-001-collapse_collection_filter_composer](RCL-001-collapse_collection_filter_composer.md)
- [RCL-001-exclude_directory_from_collection_scope](RCL-001-exclude_directory_from_collection_scope.md)
- [RCL-001-open_collection_filter_composer](RCL-001-open_collection_filter_composer.md)
- [RCL-001-open_collection_scope_menu](RCL-001-open_collection_scope_menu.md)
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

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:136`
- Contracts: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flows: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)
