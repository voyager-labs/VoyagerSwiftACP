---
interaction_id: "RCL-001-show_collection_scope_summary"
interaction_type: "display"
feature: "Define Collection Scope"
category_key: "RCL"
feature_id: "RCL-001"
status: "기획 완료"
summary: "Collection Filter Composer 안에서 현재 콜렉션 스코프를 요약해 보여주고, 기본 범위·명시적 스코프·예외 상태를 빠르게 이해할 수 있게 함"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Show Collection Scope Summary

## Intent

- 사용자가 현재 콜렉션이 어떤 범위를 대상으로 동작하는지 한눈에 이해할 수 있게 한다.
- 세부 범위를 모두 읽지 않아도 현재 스코프의 핵심 의미를 빠르게 파악할 수 있게 한다.

## Trigger / Entry Points

- Collection Filter Composer가 열릴 때
- 스코프가 추가·제거·제외·복원되어 현재 범위 의미가 바뀔 때

## Preconditions

- Collection Filter Composer가 열린 상태
- 현재 콜렉션에 대해 해석 가능한 스코프 정보가 존재하는 상태

## Expected Outcome

- 현재 스코프 요약은 최소한 아래 상태를 구분해 보여줘야 한다.
  - root-only
  - 단일 명시적 스코프
  - 다중 명시적 스코프
  - 예외 포함 상태
- 대표 정보는 사용자가 현재 콜렉션 범위를 가장 먼저 이해하는 데 필요한 한 가지 핵심 의미만 보여줘야 한다.
- 보조 정보는 대표 정보 아래 또는 옆에서 예외, 개수, 보조 위치 정보처럼 대표 정보만으로 부족한 의미를 보강해야 한다.
- 상태별 대표/보조 정보의 최소 계약은 아래를 따른다.
  - root-only: 대표 정보는 현재 페이지 또는 현재 콜렉션 문맥이 제공하는 기본 적용 범위를 설명해야 하며, 비어 있음처럼 보여주면 안 된다.
  - 단일 명시적 스코프: 대표 정보는 해당 기준 범위를 직접 가리켜야 한다.
  - 다중 명시적 스코프: 대표 정보는 여러 기준 범위가 함께 포함된 상태라는 사실을 먼저 설명해야 하며, 단일 경로명을 대표값처럼 쓰면 안 된다.
  - 예외 포함 상태: 보조 정보는 예외 존재 또는 예외 개수를 설명해야 하며, 대표 정보보다 앞에 오면 안 된다.
- 사용자는 이 요약을 보고 더 자세한 범위 편집으로 자연스럽게 이어질 수 있다.

## State Changes

- 스코프 의미가 바뀌면 요약 표시도 현재 상태에 맞게 갱신된다.
- 예외가 추가되거나 제거되면 요약에 그 변화가 반영된다.
- 단일 명시적 스코프에서 다중 명시적 스코프로 바뀌면 대표 정보는 단일 범위 이름에서 다중 범위 요약 형태로 바뀌어야 한다.
- 마지막 명시적 스코프가 제거되면 대표 정보는 다시 root-only 상태를 설명하는 형태로 돌아가야 한다.

## User-visible Feedback

- 기본 범위 상태는 아무것도 선택되지 않은 빈 상태가 아니라 기본 적용 범위로 읽혀야 한다.
- 단일 명시적 스코프 상태에서는 대표 정보가 특정 기준 범위를 직접 가리켜야 한다.
- 다중 명시적 스코프 상태에서는 대표 정보가 한 개 경로를 대표값처럼 보여주면 안 되고, 여러 기준 범위가 포함된 상태라는 사실을 먼저 전달해야 한다.
- 예외가 있는 경우에는 현재 범위가 단순 나열이 아니라 포함 범위와 제외 범위의 조합으로 읽혀야 한다.
- 보조 정보는 예외 존재, 다중 범위 개수, 현재 범위의 추가 맥락처럼 대표 정보만으로 부족한 의미를 보강하는 수준으로 붙어야 하며, 대표 정보보다 먼저 보이면 안 된다.
- 다중 명시적 스코프 상태에서는 대표 정보에 특정 하나의 경로명만 남기고 나머지를 보조 정보로 밀어 넣으면 안 된다.

## Edge Cases / Failure Handling

- 명시적 스코프가 없는 경우에도 요약이 빈칸처럼 보이지 않아야 한다.
- 범위가 많아지는 경우에도 대표 정보가 특정 하나의 경로를 전체 범위처럼 오인하게 만들면 안 된다.
- 예외가 없는 경우에는 불필요한 빈 구조를 보여주지 않아야 한다.
- 예외가 하나만 있는 경우와 여러 개인 경우 모두 대표 정보의 의미를 해치지 않아야 한다.

## Acceptance Criteria

- [ ] 사용자가 Collection Filter Composer를 보고 있을 때, 현재 범위가 기본 범위 상태라면, 시스템은 이를 빈 상태가 아닌 기본 적용 범위로 읽히게 보여줘야 한다.
- [ ] 단일 명시적 스코프가 존재하는 상황에서, 사용자가 현재 범위를 보면, 시스템은 해당 기준 범위를 대표 정보로 직접 읽을 수 있게 보여줘야 한다.
- [ ] 다중 명시적 스코프가 존재하는 상황에서, 사용자가 현재 범위를 보면, 시스템은 특정 하나의 경로를 전체 대표값처럼 보여주지 않고 여러 기준 범위가 포함된 상태임을 먼저 읽을 수 있게 해야 한다.
- [ ] 예외가 존재하는 상황에서, 사용자가 현재 범위를 보면, 시스템은 포함된 기준 범위와 제외된 예외가 함께 읽히도록 요약을 갱신해야 한다.
- [ ] 사용자가 현재 범위를 볼 때, 시스템은 대표 정보에 한 가지 핵심 의미만 두고, 개수·예외·보조 위치 같은 추가 정보는 보조 정보로 분리해 보여줘야 한다.
- [ ] 마지막 명시적 스코프가 제거된 상황에서, 시스템은 요약을 다시 root-only 상태를 설명하는 표시로 전환해야 한다.

## Permissions / Dependencies

- `RCL-001-open_collection_filter_composer`
- `RCL-001-open_collection_scope_menu`
- `RCL-001-show_collection_scope_exceptions`
- Contract: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flow: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)

## Observability / Analytics

- 스코프 요약 표시 진입
- 스코프 요약 갱신
- 스코프 요약 상태 유형(root-only / single explicit / multi explicit / exception present)

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
- [RCL-001-toggle_collection_scope_subfolder_inclusion](RCL-001-toggle_collection_scope_subfolder_inclusion.md)
- [RCL-001-undo_collection_filter_changes](RCL-001-undo_collection_filter_changes.md)
## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:120`
- Contracts: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flows: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)
