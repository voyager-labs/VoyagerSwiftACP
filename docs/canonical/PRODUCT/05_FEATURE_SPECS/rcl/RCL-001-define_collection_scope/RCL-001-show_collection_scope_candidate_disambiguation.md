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

- 검색 결과에서 동명 폴더를 위치 정보와 보조 표시로 구분해 원하는 범위를 오인 없이 선택할 수 있게 함.
- `RCL-001`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- 사용자가 Collection Filter Composer를 열거나 scope summary/menu에서 범위 편집을 시작할 때 호출된다.
- scope candidate 선택, 예외 복원, include-subfolders 토글, undo/redo 입력이 발생할 때 호출된다.

## Preconditions

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 scope, query, condition draft를 읽고 갱신할 수 있어야 한다.

## Expected Outcome

- 검색 결과에서 동명 폴더를 위치 정보와 보조 표시로 구분해 원하는 범위를 오인 없이 선택할 수 있게 함.
- current scope는 빈 값이 아니라 root-only 또는 명시적 scope 집합으로 계산되어야 한다.
- scope 변경 뒤에는 최근 변경 1건 기준의 피드백과 undo/redo 가능 상태가 갱신되어야 한다.

## State Changes

- scope draft, exception 목록, include-subfolders 값, history/redoHistory를 필요한 범위에서 갱신한다.
- candidate 검색은 기본 후보, 검색 결과, no-results 상태 중 하나로 정리된다.
- scope 의미 계산은 기준 범위 합집합, include-subfolders 해석, exception 차감 순서를 따른다.
- display interaction은 원본 데이터 자체를 임의로 변경하지 않고 표시 가능한 view state를 계산한다.

## User-visible Feedback

- 현재 scope summary, 후보 목록, 예외 목록, 변경 피드백을 같은 Composer surface 안에 표시한다.
- 동명 후보는 위치 보조 정보를 함께 보여 오선택을 줄인다.
- 실패 또는 지연 상태는 scope가 비었다는 의미로 표시하지 않는다.

## Edge Cases / Failure Handling

- 현재 scope와 같은 candidate는 추가 후보로 반복 노출하지 않는다.
- exception은 현재 기준 범위 아래에 속한 하위 범위에만 적용한다.
- undo는 최근 1건만 되돌리고 redo는 가장 최근 undo 1건만 다시 적용한다.

## Acceptance Criteria

- [ ] Collection Filter Composer가 열린 상황에서 scope를 변경하면 current scope summary가 새 의미로 갱신되어야 한다.
- [ ] 동명 candidate가 있는 상황에서 검색 결과를 표시하면 위치 보조 정보가 함께 보여야 한다.
- [ ] scope 변경 직후 undo를 실행하면 직전 scope 의미로 복원되어야 한다.

## Permissions / Dependencies

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 scope, query, condition draft를 읽고 갱신할 수 있어야 한다.
- 관련 UI region: `file_manager_window.content_pane.content_header.collection_filter_composer`
- [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)의 scope 상태 vocabulary를 따른다.

## Observability / Analytics

- interaction 실행 여부
- 요청/적용 성공 여부
- 실패 reason과 recovery action
- 마지막으로 적용된 filter snapshot

## Related Interactions

- [RCL-001-open_collection_filter_composer](RCL-001-open_collection_filter_composer.md)
- [RCL-001-collapse_collection_filter_composer](RCL-001-collapse_collection_filter_composer.md)
- [RCL-001-open_collection_scope_menu](RCL-001-open_collection_scope_menu.md)
- [RCL-001-show_collection_scope_summary](RCL-001-show_collection_scope_summary.md)
- [RCL-001-search_collection_scope_candidates](RCL-001-search_collection_scope_candidates.md)
- [RCL-001-add_directory_to_collection_scope](RCL-001-add_directory_to_collection_scope.md)
- [RCL-001-remove_directory_from_collection_scope](RCL-001-remove_directory_from_collection_scope.md)
- [RCL-001-exclude_directory_from_collection_scope](RCL-001-exclude_directory_from_collection_scope.md)
- [RCL-001-restore_directory_to_collection_scope](RCL-001-restore_directory_to_collection_scope.md)
- [RCL-001-toggle_collection_scope_subfolder_inclusion](RCL-001-toggle_collection_scope_subfolder_inclusion.md)
- [RCL-001-show_collection_scope_exceptions](RCL-001-show_collection_scope_exceptions.md)
- [RCL-001-show_collection_scope_change_feedback](RCL-001-show_collection_scope_change_feedback.md)
- [RCL-001-undo_collection_filter_changes](RCL-001-undo_collection_filter_changes.md)
- [RCL-001-redo_collection_filter_changes](RCL-001-redo_collection_filter_changes.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:122`
- Contracts: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flows: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)
- Implementation references: `../voyager-app/docs/features/composer.md`, `../voyager-app/docs/features/entries-collections.md`, `../voyager-app/apps/macos/Voyager/Voyager/04_Features/Composer/Reducer/ComposerFeature.swift`, `../voyager-app/apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`
