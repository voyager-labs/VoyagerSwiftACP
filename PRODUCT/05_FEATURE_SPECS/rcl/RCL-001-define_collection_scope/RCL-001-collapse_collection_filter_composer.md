---
interaction_id: "RCL-001-collapse_collection_filter_composer"
interaction_type: "command"
feature: "Define Collection Scope"
category_key: "RCL"
feature_id: "RCL-001"
status: "배포 완료"
summary: "Collection Filter Composer를 닫아 페이지 타이틀 바 기본 상태로 전환하며, 미저장 변경은 유지"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "ESC"
---

# Collapse Collection Filter Composer

## Intent

- 사용자가 Collection Filter Composer shared shell을 닫고 페이지 타이틀 바 기본 상태로 돌아갈 수 있게 한다.
- Composer를 닫더라도 미저장 변경과 진행 중 파이프라인 상태는 잃지 않게 한다.

## Trigger / Entry Points

- 사용자가 `ESC`를 입력할 때
- 사용자가 Composer 닫기 액션을 실행할 때

## Preconditions

- Collection Filter Composer가 열린 상태

## Expected Outcome

- Collection Filter Composer가 화면에서 닫혀야 한다.
- 페이지 타이틀 바는 기본 상태로 돌아가야 한다.
- 미저장 변경이 있으면 닫힌 뒤에도 미저장 상태는 유지되어야 한다.
- 진행 중 파이프라인이 있으면 Composer가 닫혀도 그 진행 상태는 계속 유지되어야 한다.
- 이 동작은 shared shell의 표시 상태만 제어한다.
- query 기반 구성은 RCL-004, 개별 조건 수동 편집은 RCL-005에서 정의한다.

## State Changes

- Composer 표시 상태가 열림에서 닫힘으로 전환된다.
- 페이지 헤더는 기본 상태로 복귀한다.
- 미저장 변경 상태는 유지된다.
- 진행 중 파이프라인은 중단되지 않고 계속 유지된다.

## User-visible Feedback

- Composer가 닫히면 사용자는 편집 표면이 사라졌음을 즉시 이해할 수 있어야 한다.
- 미저장 변경이 남아 있으면 타이틀 바 또는 동등한 위치에 미저장 상태가 계속 보여야 한다.
- 진행 중 파이프라인이 있으면 Composer가 닫혀도 사용자는 진행 중 상태를 잃지 않아야 한다.

## Edge Cases / Failure Handling

- 미저장 필터 변경이 존재하는 경우
- 필터 편집 중 호출되는 경우
- 필터 생성 파이프라인이 실행 중인 상태에서 호출되는 경우

## Acceptance Criteria

- [ ] Collection Filter Composer가 열린 상태일 때, 사용자가 해당 인터랙션을 호출하면, Collection
      Filter Composer가 닫히고 페이지 타이틀 바 기본 상태로 전환함
- [ ] 미저장 필터 변경이 존재하는 상태일 때, 사용자가 해당 인터랙션을 호출하면, 변경을 폐기하지 않고
      유지하며, 타이틀바에 미저장 상태를 표시함
- [ ] 필터 편집 중인 상태일 때, 사용자가 해당 인터랙션을 호출하면, 현재 편집 상태를 보존한 채 Collection Filter Composer를 닫음
- [ ] 필터 변경이 진행 중인 상태일 때, 사용자가 해당 인터랙션을 호출하면, 현재 진행 상태를 보존한 채 Collection Filter Composer를 닫음
- [ ] 필터 생성 파이프라인이 실행 중인 상태에서 사용자가 해당 인터랙션을 호출하면, 파이프라인은
      중단하지 않고 진행 상태를 유지함

## Permissions / Dependencies

- `RCL-002-indicate_unsaved_collection_filter_changes`
- Contract: [../contracts/collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flow: [../flows/collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)

## Observability / Analytics

- Composer 닫기
- 닫기 시 미저장 변경 존재 여부
- 닫기 시 파이프라인 진행 여부

## Related Interactions

- [RCL-001-add_directory_to_collection_scope](RCL-001-add_directory_to_collection_scope.md)
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
- [RCL-001-undo_collection_filter_changes](RCL-001-undo_collection_filter_changes.md)
## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:105`
- Contracts: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flows: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)
