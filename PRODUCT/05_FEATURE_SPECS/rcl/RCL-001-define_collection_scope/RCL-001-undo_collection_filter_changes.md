---
interaction_id: "RCL-001-undo_collection_filter_changes"
interaction_type: "command"
feature: "Define Collection Scope"
category_key: "RCL"
feature_id: "RCL-001"
status: "배포 완료"
summary: "최근 수행한 필터 또는 스코프 편집 변경을 한 단계 되돌려 이전 상태로 복원"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "⌘Z"
---

# Undo Collection Filter Changes

## Intent

- 사용자가 방금 적용한 필터 또는 스코프 변경을 빠르게 취소해 직전 상태로 돌아갈 수 있게 한다.

## Trigger / Entry Points

- 키보드 단축키 `⌘Z`
- 변경 직후 노출되는 되돌리기

## Preconditions

- Generate Filter Changes from Query가 실행 중이지 않은 상태
- 필터 편집 히스토리가 존재하는 상태

## Expected Outcome

- 되돌리기는 가장 최근 1건의 필터 편집 또는 스코프 변경만 대상으로 한다.
- 현재 범위의 의미와 표시가 직전 상태와 일치하게 복원되어야 한다.
- 스코프 변경으로 인해 달라졌던 결과 해석도 같은 직전 상태 기준으로 돌아가야 한다.
- undo 후에는 필요 시 `redo_available` 상태가 생겨야 한다.
- undo 전에는 현재 변경이 `undo_available` 상태인지 읽을 수 있어야 하고, undo 후에는 필요 시 `redo_available` 상태로 이어질 수 있어야 한다.


## State Changes

- 가장 최근 변경 1건 기준으로 현재 필터 상태가 직전 상태로 복원된다.
- 현재 범위 요약, 조건 상태, 변경 피드백이 같은 직전 상태에 맞게 갱신된다.
- 되돌리기가 완료되면 이전 변경을 가리키던 피드백은 현재 상태 기준으로 교체되거나 사라져야 한다.

## User-visible Feedback

- 되돌리기 전에는 어떤 변경이 취소 대상인지 읽을 수 있어야 한다.
- 되돌리기 후에는 현재 범위 의미가 이전 상태로 복원되었음을 읽을 수 있어야 한다.
- 되돌리기 후에는 결과가 왜 이전 상태로 돌아갔는지도 함께 이해할 수 있어야 한다.
- 되돌릴 변경이 없는 상태에서 사용자가 되돌리기를 시도하면, 시스템은 현재 되돌릴 항목이 없다는 피드백을 보여주거나 동일한 의미의 no-op 상태를 명시적으로 보여줘야 한다.
- 사용자가 되돌릴 수 있는 상황에서는 contract 용어 기준의 `되돌리기 가능` 상태가 함께 읽혀야 한다.

## Edge Cases / Failure Handling

- 되돌리기 가능한 히스토리가 없는 경우에는 되돌리기 진입을 허용하면 안 되며, 기존 피드백 안에 되돌릴 변경이 없다는 상태를 함께 보여줘야 한다.
- 연속으로 여러 변경이 있었더라도 가장 최근 변경 1건만 복원 대상으로 삼아야 한다.
- 스코프 변경과 조건 변경이 연달아 섞인 경우에도 현재 피드백이 가리키는 가장 최근 변경과 같은 대상을 되돌려야 한다.
- 되돌리기 적용이 실패하면 복원된 것처럼 보이는 상태를 보여주면 안 되며, 현재 상태 유지와 되돌리기 실패 사실을 함께 보여줘야 한다.

## Acceptance Criteria

- [ ] 필터 편집 내역이 존재하는 상황에서, 사용자가 되돌리기를 호출하면, 시스템은 가장 최근 변경 1건만 한 단계 되돌려야 한다.
- [ ] 직전 변경이 스코프 변경인 상황에서, 사용자가 되돌리기를 실행하면, 시스템은 현재 범위 의미와 표시를 이전 상태로 복원해야 한다.
- [ ] 되돌리기 이후에는 변경 피드백이 현재 상태에 맞게 갱신되거나 사라져야 한다.
- [ ] 직전 스코프 변경으로 결과 해석이 달라진 상황에서, 사용자가 되돌리기를 실행하면, 시스템은 결과 변화도 이전 범위 상태와 연결해 이해할 수 있게 해야 한다.
- [ ] 되돌리기 가능한 히스토리가 없는 상황에서는, 시스템이 되돌리기 진입을 허용하지 않거나 현재 되돌릴 변경이 없다는 상태를 명확히 보여줘야 한다.
- [ ] undo가 완료된 상황에서 다시 적용 가능한 최근 변경이 있다면, 시스템은 `redo_available` 상태를 만들 수 있어야 한다.
- [ ] 변경 피드백이 현재 보이지 않는 상황에서 사용자가 되돌리기를 시도하더라도, 시스템은 되돌릴 변경이 없다는 상태를 명시적으로 보여주거나 같은 의미의 no-op 피드백을 제공해야 한다.

## Permissions / Dependencies

- 필터 편집 히스토리가 유지되는 상태여야 한다.
- 현재 범위 요약과 변경 피드백이 되돌린 상태와 정합하게 갱신되어야 한다.
- 이 문서는 최소 되돌리기 경험을 우선 설명하며, 장기 변경 이력 탐색이나 확장된 다단계 되돌리기 정책은 범위 밖이다.
- Contract: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flow: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)

## Observability / Analytics

- 되돌리기 호출
- 되돌리기 대상 변경 유형(스코프 / 조건)
- 되돌리기 성공 / 실패

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
- [RCL-001-toggle_collection_scope_subfolder_inclusion](RCL-001-toggle_collection_scope_subfolder_inclusion.md)
## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:135`
- Contracts: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flows: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)
