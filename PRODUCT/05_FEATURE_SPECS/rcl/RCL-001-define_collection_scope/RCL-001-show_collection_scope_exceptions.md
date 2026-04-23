---
interaction_id: "RCL-001-show_collection_scope_exceptions"
interaction_type: "display"
feature: "Define Collection Scope"
category_key: "RCL"
feature_id: "RCL-001"
status: "기획 완료"
summary: "현재 기준 범위 아래에서 제외된 예외 목록을 인라인으로 보여줘 현재 범위 의미를 함께 이해할 수 있게 함"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Show Collection Scope Exceptions

## Intent

- 사용자가 현재 범위를 볼 때 어떤 하위 범위가 예외로 빠져 있는지 함께 이해할 수 있게 한다.
- 예외 목록이 현재 스코프 surface 안에서 자연스럽게 읽히도록 한다.

## Trigger / Entry Points

- 현재 스코프에 하나 이상의 예외가 존재할 때
- 예외가 추가되거나 복원되어 현재 범위 의미가 바뀔 때

## Preconditions

- Collection Filter Composer가 열린 상태
- 기준 범위가 존재하는 상태

## Expected Outcome

- 예외가 존재하면 기준 범위 아래에 예외 목록을 인라인으로 보여준다.
- 예외가 없으면 예외 영역 자체를 숨기거나 비노출 상태로 유지한다.
- 각 예외 항목은 표시 전용이 아니라 복원 가능한 항목으로 보여야 한다.
- 예외 목록이 보이는 상태는 현재 스코프가 예외 포함 상태(`exception_present`)라는 뜻이다.
- 예외 포함 상태(`exception_present`)가 아닌 상태에서는 예외 목록을 보이면 안 된다.


## State Changes

- 예외가 추가되거나 제거되면 목록 표시가 현재 상태에 맞게 갱신된다.
- 마지막 예외가 사라지면 예외 목록도 함께 사라진다.
- 예외가 하나일 때와 여러 개일 때 모두 같은 위치 체계를 유지해야 한다.

## User-visible Feedback

- 예외 목록은 기준 범위와 같은 레벨의 후보 목록처럼 보이면 안 된다.
- 예외 목록은 기준 범위 아래의 보조 정보로 읽혀야 한다.
- 예외 항목은 현재 빠져 있는 하위 범위를 식별할 수 있어야 하고, 같은 행 또는 인접한 제어에서 복원 흐름으로 이어질 수 있어야 한다.

## Edge Cases / Failure Handling

- 예외가 하나만 있는 경우와 여러 개인 경우 모두 같은 구조로 읽혀야 한다.
- 예외가 없는 상태에서는 빈 예외 목록이나 placeholder를 남기면 안 된다.
- 일부 예외 정보가 부족하더라도 최소한 예외의 폴더명 또는 위치 정보 중 하나는 표시되어 어떤 하위 범위가 빠져 있는지 식별 가능해야 한다.
- 다중 기준 범위 상태에서도 예외는 소속 기준 범위 아래에 묶여 읽혀야 하며, 독립 후보처럼 섞이면 안 된다.

## Acceptance Criteria

- [ ] 기준 범위와 예외가 함께 존재하는 상황에서, 사용자가 현재 스코프를 보면, 시스템은 예외를 기준 범위 아래 인라인 목록으로 보여줘야 한다.
- [ ] 사용자가 예외 항목을 보면, 시스템은 예외가 기준 범위의 보조 정보로 읽히게 해야 하며, 새 후보 목록처럼 보이게 하면 안 된다.
- [ ] 예외가 없는 상황에서는, 시스템이 불필요한 빈 목록이나 빈 제목 없이 현재 범위를 보여줘야 한다.
- [ ] 예외 항목이 보이는 상황에서, 시스템은 해당 항목에서 직접 복원 흐름으로 이어질 수 있는 조작을 제공해야 한다.
- [ ] 다중 기준 범위 상태에서 예외가 존재하는 상황에서는, 시스템은 예외를 해당 기준 범위 아래에 묶어 보여줘야 한다.
- [ ] 예외 목록이 보이는 상황은 `exception_present` 상태와 일치해야 한다.

## Permissions / Dependencies

- `RCL-001-exclude_directory_from_collection_scope`
- `RCL-001-restore_directory_to_collection_scope`
- Contract: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flow: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)

## Observability / Analytics

- 예외 목록 표시
- 예외 복원 진입
- 예외 항목 개수

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
- [RCL-001-show_collection_scope_summary](RCL-001-show_collection_scope_summary.md)
- [RCL-001-toggle_collection_scope_subfolder_inclusion](RCL-001-toggle_collection_scope_subfolder_inclusion.md)
- [RCL-001-undo_collection_filter_changes](RCL-001-undo_collection_filter_changes.md)
## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:128`
- Contracts: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flows: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)
