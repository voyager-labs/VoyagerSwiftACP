---
interaction_id: "RCL-001-search_collection_scope_candidates"
interaction_type: "input"
feature: "Define Collection Scope"
category_key: "RCL"
feature_id: "RCL-001"
status: "기획 완료"
summary: "스코프 편집창 안에서 폴더 후보를 검색해 기본 후보 목록에서 검색 결과 상태로 전환"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Search Collection Scope Candidates

## Intent

- 사용자가 스코프 편집창 안에서 원하는 폴더 후보를 빠르게 찾을 수 있게 한다.
- 기본 후보 목록과 검색 결과 목록을 자연스럽게 오가며 범위를 고를 수 있게 한다.

## Trigger / Entry Points

- 스코프 편집창 안의 검색 입력 영역에 문자를 입력할 때
- 기존 검색어를 수정하거나 지울 때

## Preconditions

- Collection Filter Composer가 열린 상태
- 스코프 편집창이 열린 상태
- 검색 가능한 후보 목록이 준비된 상태

## Expected Outcome

- 검색어가 비어 있으면 기본 후보 목록이 보인다.
- 검색어를 입력하면 사용자는 검색 결과 상태로 전환된 것을 이해할 수 있어야 한다.
- 검색 결과가 없으면 단순 빈 목록이 아니라 결과 없음 상태로 읽혀야 한다.

## State Changes

- 현재 검색어가 갱신된다.
- 후보 목록 상태가 기본 후보, 검색 결과, 결과 없음 중 하나로 전환된다.
- 검색어를 지우면 기본 후보 상태로 복귀한다.

## User-visible Feedback

- 사용자는 지금 기본 후보를 보고 있는지, 검색 결과를 보고 있는지 자연스럽게 이해할 수 있어야 한다.
- 검색 결과가 없을 때는 다음 행동을 알 수 있는 결과 없음 상태가 보여야 한다.
- 검색은 트리 전체를 펼쳐 필터링하는 흐름이 아니라 원하는 후보로 빠르게 이동하는 흐름으로 읽혀야 한다.

## Edge Cases / Failure Handling

- 검색어를 빠르게 입력하고 지우는 경우에도 상태 전환이 일관되어야 한다.
- 검색 결과가 하나도 없는 경우에도 기존 화면이 깨지지 않아야 한다.
- 동일 이름 후보가 여러 개 보이면 별도 구분 표시와 함께 읽혀야 한다.

## Acceptance Criteria

- [ ] 검색어가 비어 있는 상황에서, 사용자가 스코프 편집창을 보면, 시스템은 기본 후보 목록을 기본 상태로 보여줘야 한다.
- [ ] 검색어를 입력했을 때, 결과가 존재하면, 시스템은 검색 결과 상태로 전환되어야 한다.
- [ ] 검색 결과가 없는 상황에서, 사용자가 검색을 수행하면, 시스템은 결과 없음 상태와 검색 수정 또는 기본 후보 복귀 가능성을 보여줘야 한다.
- [ ] 사용자가 검색어를 지우면, 시스템은 기본 후보 상태로 자연스럽게 돌아가야 한다.

## Permissions / Dependencies

- `RCL-001-open_collection_scope_menu`
- `RCL-001-show_collection_scope_candidate_disambiguation`
- Contract: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flow: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)

## Observability / Analytics

- 스코프 후보 검색 진입
- 검색 결과 없음 노출
- 검색어 지우기 후 기본 후보 복귀

## Related Interactions

- [RCL-001-add_directory_to_collection_scope](RCL-001-add_directory_to_collection_scope.md)
- [RCL-001-collapse_collection_filter_composer](RCL-001-collapse_collection_filter_composer.md)
- [RCL-001-exclude_directory_from_collection_scope](RCL-001-exclude_directory_from_collection_scope.md)
- [RCL-001-open_collection_filter_composer](RCL-001-open_collection_filter_composer.md)
- [RCL-001-open_collection_scope_menu](RCL-001-open_collection_scope_menu.md)
- [RCL-001-redo_collection_filter_changes](RCL-001-redo_collection_filter_changes.md)
- [RCL-001-remove_directory_from_collection_scope](RCL-001-remove_directory_from_collection_scope.md)
- [RCL-001-restore_directory_to_collection_scope](RCL-001-restore_directory_to_collection_scope.md)
- [RCL-001-show_collection_scope_candidate_disambiguation](RCL-001-show_collection_scope_candidate_disambiguation.md)
- [RCL-001-show_collection_scope_change_feedback](RCL-001-show_collection_scope_change_feedback.md)
- [RCL-001-show_collection_scope_exceptions](RCL-001-show_collection_scope_exceptions.md)
- [RCL-001-show_collection_scope_summary](RCL-001-show_collection_scope_summary.md)
- [RCL-001-toggle_collection_scope_subfolder_inclusion](RCL-001-toggle_collection_scope_subfolder_inclusion.md)
- [RCL-001-undo_collection_filter_changes](RCL-001-undo_collection_filter_changes.md)
## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:121`
- Contracts: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flows: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)
