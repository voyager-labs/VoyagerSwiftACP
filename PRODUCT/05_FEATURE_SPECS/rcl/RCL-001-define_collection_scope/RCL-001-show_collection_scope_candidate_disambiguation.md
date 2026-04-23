---
interaction_id: "RCL-001-show_collection_scope_candidate_disambiguation"
interaction_type: "display"
feature: "Define Collection Scope"
category_key: "RCL"
feature_id: "RCL-001"
status: "기획 완료"
summary: "검색 결과에서 동명 폴더를 위치 정보와 보조 표시로 구분해 원하는 범위를 오인 없이 선택할 수 있게 함"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Show Collection Scope Candidate Disambiguation

## Intent

- 같은 이름의 폴더가 여러 위치에 있을 때, 사용자가 원하는 범위를 오인 없이 구분할 수 있게 한다.
- 이름 외 보조 정보가 검색 결과 안에서 자연스럽게 읽히도록 한다.

## Trigger / Entry Points

- 스코프 후보 검색 결과에 같은 이름의 폴더가 둘 이상 나타날 때
- 기본 후보 목록이나 검색 결과에서 추가 구분 정보가 필요할 때

## Preconditions

- 스코프 편집창이 열린 상태
- 현재 후보 목록에 구분이 필요한 항목이 존재하는 상태

## Expected Outcome

- 각 후보는 이름 외에 최소 하나의 위치 식별 정보를 함께 보여준다.
- 사용자는 같은 이름의 폴더를 결과 row만 보고도 구분할 수 있어야 한다.

## State Changes

- 후보 목록이 바뀌면 구분 표기도 그 결과에 맞게 갱신된다.
- hover나 선택 상태에서도 어떤 후보인지 계속 읽을 수 있는 표시를 유지한다.

## User-visible Feedback

- 이름이 같더라도 최소 부모 폴더명, 경로 suffix, 저장 위치 중 하나는 표시되어야 한다.
- 후보 이름은 항상 가장 먼저 보여야 하고, 구분 정보는 그 뒤의 보조 정보로 표시되어야 한다.
- 구분 정보는 전체 절대 경로를 항상 노출하는 방식이 아니라, 오인 선택을 막는 최소 정보만 사용해야 한다.

## Edge Cases / Failure Handling

- 이름과 부모 위치가 모두 긴 경우에도 중요한 구분 정보가 묻히지 않아야 한다.
- 일부 보조 정보가 부족한 경우에도 최소한 안전하게 선택 가능한 상태를 유지해야 한다.
- 동명 폴더가 없는 경우에는 불필요한 구분 표시가 과하게 드러나지 않아야 한다.
- 동일한 부모 이름까지 겹치는 경우에는 저장 위치 또는 더 긴 경로 suffix로 추가 구분되어야 한다.

## Acceptance Criteria

- [ ] 같은 이름의 폴더가 여러 위치에 존재하는 상황에서, 사용자가 검색 결과를 보면, 시스템은 각 후보를 오인 없이 구분할 수 있는 보조 정보를 함께 보여줘야 한다.
- [ ] 사용자가 특정 후보를 hover하거나 선택하더라도, 시스템은 어느 후보인지 계속 읽을 수 있는 구분 표시를 유지해야 한다.
- [ ] 일부 보조 정보가 부족한 상황에서도, 시스템은 최소한 안전하게 선택 가능한 상태를 유지해야 한다.
- [ ] 같은 이름의 폴더 후보가 여러 개일 때, 시스템은 각 후보의 이름 뒤에 최소 하나의 위치 식별 정보를 표시해야 한다.
- [ ] 구분 정보는 후보 이름보다 먼저 보이면 안 되며, 후보 이름을 가리는 전체 경로 나열 방식이 기본값이 되면 안 된다.
- [ ] 부모 이름까지 같은 경우에는 시스템이 추가 구분 정보로 저장 위치 또는 더 긴 경로 suffix를 사용해야 한다.

## Permissions / Dependencies

- `RCL-001-search_collection_scope_candidates`
- Contract: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flow: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)

## Observability / Analytics

- 동명 후보 구분 표시 노출
- 동명 후보 선택

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
- [RCL-001-show_collection_scope_change_feedback](RCL-001-show_collection_scope_change_feedback.md)
- [RCL-001-show_collection_scope_exceptions](RCL-001-show_collection_scope_exceptions.md)
- [RCL-001-show_collection_scope_summary](RCL-001-show_collection_scope_summary.md)
- [RCL-001-toggle_collection_scope_subfolder_inclusion](RCL-001-toggle_collection_scope_subfolder_inclusion.md)
- [RCL-001-undo_collection_filter_changes](RCL-001-undo_collection_filter_changes.md)
## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:122`
- Contracts: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flows: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)
