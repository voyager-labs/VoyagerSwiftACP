---
interaction_id: "RCL-001-add_directory_to_collection_scope"
interaction_type: "command"
feature: "Define Collection Scope"
category_key: "RCL"
feature_id: "RCL-001"
status: "배포 완료"
summary: "스코프 편집창에서 명시적 범위를 추가해 현재 콜렉션의 대상 범위를 더 구체적으로 정의"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Add Directory To Collection Scope

## Intent

- 사용자가 현재 콜렉션의 대상 범위를 더 명확하게 정의하기 위해 명시적 스코프를 추가한다.
- 이 문서는 `root_only`, `single_explicit_scope`, `multi_explicit_scope`, `exception_present` 상태 전환의 add 경로를 다룬다.

## Trigger / Entry Points

- 스코프 편집창에서 후보 범위를 선택
- 검색 결과에서 특정 범위를 선택

## Preconditions

- Collection Filter Composer가 열린 상태
- 스코프 편집창이 열린 상태
- Generate Filter Changes from Query가 실행 중이지 않은 상태

## Expected Outcome

- root-only 상태에서는 첫 명시적 스코프가 추가되어 현재 범위가 더 구체적으로 정의된다.
- 명시적 스코프가 이미 있으면 새 범위가 기존 기준 범위 목록에 추가된다.
- 이미 포함된 범위는 중복으로 추가되지 않는다.
- 이 동작은 `root_only`에서 `single_explicit_scope`로, 필요 시 `single_explicit_scope`에서 `multi_explicit_scope`로 전환되는 흐름이다.
- 예외가 이미 있으면 새 기준 범위 추가 뒤에도 `exception_present` 상태가 유지될 수 있다.
- add 직후 현재 스코프는 `single_explicit_scope`(단일 명시적 스코프) 또는 `multi_explicit_scope`(다중 명시적 스코프) 상태로 읽혀야 하며, 필요 시 `exception_present`(예외 포함 상태)를 함께 유지할 수 있다.

## State Changes

- root-only 상태는 명시적 스코프 상태로 전환될 수 있다.
- 명시적 스코프 목록이 갱신된다.
- 현재 범위 요약과 현재 필터 내용이 함께 갱신된다.
- 기존 예외가 새 기준 범위 목록과 더 이상 연결되지 않는 경우, 시스템은 해당 예외를 현재 스코프에서 제거해야 한다.
- 기존 예외가 여전히 하나 이상의 기준 범위 아래에 포함되는 경우에는 그대로 유지해야 한다.
- 결과적으로 예외 포함 상태(`exception_present`)와 되돌리기 가능(`undo_available`) 상태가 함께 갱신될 수 있다.
- 변경 직후에는 변경 피드백(`change_feedback_visible`) 상태도 함께 갱신될 수 있다.
- 결과적으로 `single_explicit_scope` / `multi_explicit_scope` / `exception_present` / `change_feedback_visible` / `undo_available` 상태가 함께 재해석될 수 있다.

## User-visible Feedback

- 추가 직후 현재 범위가 어떻게 바뀌었는지 이해할 수 있어야 한다.
- 동명 폴더 검색 결과에서는 선택한 항목이 어느 위치의 폴더인지 식별 가능해야 한다.
- 변경 직후 변경 피드백 또는 undo 가능 여부가 함께 드러나야 한다.

## Edge Cases / Failure Handling

- 이미 포함된 범위를 다시 추가하려는 경우에는 중복 추가 없이 현재 상태를 유지한다.
- 동명 폴더가 여러 개인 경우에는 보조 정보로 구분 가능해야 한다.
- 검색 결과가 없으면 추가 동작이 아니라 검색 수정 또는 기본 후보 복귀로 이어져야 한다.
- 새 기준 범위 추가로 인해 일부 예외가 더 이상 어떤 기준 범위에도 속하지 않게 되면, 해당 예외는 제거되어야 한다.

## Acceptance Criteria

- [ ] root-only 상태에서, 사용자가 특정 범위를 추가하면, 현재 콜렉션은 명시적 스코프 상태로 전환되어야 한다.
- [ ] 하나 이상의 명시적 스코프가 있는 상황에서, 사용자가 다른 범위를 추가하면, 기존 범위는 유지되고 새 범위가 함께 반영되어야 한다.
- [ ] 이미 포함된 범위를 다시 추가하려는 상황에서, 사용자가 해당 범위를 선택하면, 시스템은 중복 추가 없이 현재 범위를 유지해야 한다.
- [ ] 동명 폴더 후보가 여러 개인 상황에서, 사용자가 보조 위치 정보를 보고 특정 후보를 선택하면, 의도한 범위가 추가되어야 한다.
- [ ] 새 기준 범위를 추가한 뒤 기존 예외가 어떤 기준 범위에도 속하지 않게 되면, 시스템은 해당 예외를 현재 스코프에서 제거해야 한다.
- [ ] 새 기준 범위를 추가한 뒤 기존 예외가 여전히 하나 이상의 기준 범위 아래에 속하면, 시스템은 해당 예외를 유지해야 한다.

## Permissions / Dependencies

- `RCL-001-open_collection_scope_menu`
- 변경 피드백이 존재하는 경우 현재 범위 변화와 자연스럽게 연결되어야 한다.
- 기준 범위 추가는 예외 규칙과 모순되지 않아야 하며, 예외의 유효 여부는 "하나 이상의 현재 기준 범위 아래에 포함되는가"를 기준으로 해석해야 한다.
- Contract: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flow: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)

## Observability / Analytics

- 명시적 스코프 추가 시도
- 추가 성공
- 중복 추가 방지

## Related Interactions

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
- [RCL-001-undo_collection_filter_changes](RCL-001-undo_collection_filter_changes.md)
## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:123`
- Contracts: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flows: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)
