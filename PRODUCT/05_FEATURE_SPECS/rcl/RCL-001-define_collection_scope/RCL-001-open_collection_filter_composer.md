---
interaction_id: "RCL-001-open_collection_filter_composer"
interaction_type: "command"
feature: "Define Collection Scope"
category_key: "RCL"
feature_id: "RCL-001"
status: "배포 완료"
summary: "Entries View 상단에서 Collection Filter Composer를 열어 현재 콜렉션의 스코프 요약, query 입력, 조건 편집 영역이 함께 보이는 shared shell 상태로 전환"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "edit_menu"
shortcut: "⌘F"
---

# Open Collection Filter Composer

## Intent

- 사용자가 Collection Filter Composer shared shell에 진입해 현재 콜렉션의 스코프 요약을 중심으로 필터 작업을 위한 컨텍스트를 확보할 수 있게 한다.
- 사용자는 현재 범위가 기본 범위 상태인지, 명시적 스코프가 있는지, 예외가 있는지의 기본 의미를 읽을 수 있어야 한다.

## Trigger / Entry Points

- Entries View 상단에서 Collection Filter Composer를 호출
- 저장된 콜렉션을 연 뒤 현재 콜렉션의 범위(스코프)를 확인하거나 조정하려는 흐름에서 진입

## Preconditions

- 현재 페이지가 Collection Filter Composer를 지원하는 상태

## Expected Outcome

- Collection Filter Composer가 열리고, 현재 콜렉션의 범위(스코프) 요약이 사용자가 읽을 수 있는 형태로 노출된다.
- Composer는 shared shell로서 필터 정의 표면을 포함할 수 있으나, 이 문서는 정의를 생성하거나 편집하는 semantics를 설명하지 않는다.
- 사용자는 현재 범위 요약 영역을 통해 범위 편집 진입점을 확인할 수 있다.
- 스코프 관련 정보와 컨디션 관련 정보는 같은 Composer 안에 있더라도 다른 역할로 읽혀야 한다.
- 이 문서는 Composer shell 진입과 스코프 요약 문맥을 설명하며, query 기반 필터 재구성은 RCL-004, 개별 조건 수동 편집은 RCL-005에서 정의한다.

## State Changes

- Composer가 열린 상태가 된다.
- Collection Filter Composer가 상단 헤더의 primary context로 활성화된다.
- 미저장 변경이 있었다면 그 변경 맥락을 유지한 채 Composer 컨텍스트로 전환된다.

## User-visible Feedback

- 현재 기본 범위 상태인지 명시적 스코프가 있는지 요약이 보여야 한다.
- 예외가 존재하면 현재 범위가 단순 경로 나열이 아님을 알 수 있어야 한다.
- 미저장 변경이 있으면 해당 상태가 유지된 채 composer가 열린다.

## Edge Cases / Failure Handling

- 이미 Collection Filter Composer가 열린 상태에서 다시 호출되면 중복된 창을 만들지 않고 현재 입력 맥락으로 복귀한다.
- 미저장 필터 변경이 존재하는 상태에서 다시 진입해도 현재 편집 중 상태를 잃지 않는다.

## Acceptance Criteria

- [ ] 현재 페이지가 필터 편집을 지원하는 상황에서, 사용자가 해당 인터랙션을 호출하면, Collection Filter Composer가 열리고 현재 필터 편집 상태가 표시되어야 한다.
- [ ] composer가 이미 열린 상황에서, 사용자가 해당 인터랙션을 다시 호출하면, 중복 창을 만들지 않고 현재 편집 맥락을 유지해야 한다.
- [ ] 미저장 변경이 존재하는 상황에서, 사용자가 composer를 열면, 해당 변경이 유지된 상태로 현재 범위와 조건을 다시 확인할 수 있어야 한다.

## Permissions / Dependencies

- 필터 편집을 지원하는 페이지 맥락이어야 한다.
- 현재 범위 요약 표시는 Composer 안에서 일관되게 유지되어야 한다.
- 현재 문서는 범위 요약에 대한 기본 계약을 설명하며, 더 세부적인 범위 표시 방식은 후속 문서에서 구체화될 수 있다.
- Contract: [../contracts/collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flow: [../flows/collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)

## Observability / Analytics

- Composer 열기 진입
- 열릴 당시 스코프 상태 유형(root-only / 명시적 스코프 / 예외 포함 여부)

## Related Interactions

- [RCL-001-add_directory_to_collection_scope](RCL-001-add_directory_to_collection_scope.md)
- [RCL-001-collapse_collection_filter_composer](RCL-001-collapse_collection_filter_composer.md)
- [RCL-001-exclude_directory_from_collection_scope](RCL-001-exclude_directory_from_collection_scope.md)
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

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:104`
- Contracts: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flows: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)
