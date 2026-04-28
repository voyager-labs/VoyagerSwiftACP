---
interaction_id: "RCL-001-open_collection_scope_menu"
interaction_type: "command"
feature: "Define Collection Scope"
category_key: "RCL"
feature_id: "RCL-001"
status: "배포 완료"
summary: "현재 콜렉션 범위를 이해하고 편집할 수 있는 스코프 편집창을 열어 기본 후보, 검색, 범위 상태를 확인·수정할 수 있게 함"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Open Collection Scope Menu

## Intent

- 사용자가 현재 콜렉션의 대상 범위를 이해하고 수정하기 위한 스코프 편집창을 연다.

## Trigger / Entry Points

- Collection Filter Composer 안의 스코프 요약 영역에서 진입
- 현재 범위를 보여주는 표시나 관련 진입 요소를 통해 진입

## Preconditions

- Collection Filter Composer가 열린 상태

## Expected Outcome

- 현재 범위를 기준으로 한 스코프 편집창이 열린다.
- 스코프 편집창은 아래 3개 축의 조합으로 현재 상태를 보여줘야 한다.
  - 스코프 구성 상태: root-only / 단일 명시적 스코프 / 다중 명시적 스코프
  - 예외 상태: 예외 없음 / 예외 포함
  - 목록 상태: 기본 후보 / 검색 결과 / 결과 없음
- 검색어가 비어 있으면 기본 후보 목록이 먼저 보여야 하고, 검색어를 입력하면 검색 결과 상태로 전환되어야 한다.
- 현재 포함된 기준 범위와 현재 예외 상태는 새로 추가 가능한 후보 목록과 섞이지 않고, 같은 화면 안에서 서로 다른 정보 영역으로 읽혀야 한다.
- 현재 포함된 기준 범위 영역의 항목 액션은 조정 / 제거 / 예외 관리 흐름으로 해석되어야 하고, 후보 목록의 항목 액션은 add 흐름으로 해석되어야 한다.

## State Changes

- 단순히 메뉴만 열리는 것이 아니라 현재 콜렉션 범위를 편집하는 흐름이 활성화된다.
- 스코프 편집창의 기본 목록 영역은 현재 범위 주변 후보 또는 최근 방문/즐겨찾기 후보를 보여주는 상태가 된다.
- 검색어를 입력하면 기본 후보 상태는 검색 결과 상태로 전환된다.
- 결과가 없으면 결과 없음 상태로 전환되며, 이 상태에서는 add 동작 대신 검색 수정 또는 기본 후보 복귀 흐름이 우선된다.
- root-only / 단일 명시적 스코프 / 다중 명시적 스코프는 현재 어떤 기준 범위가 적용되는지를 설명하는 기본 상태다.
- 예외 존재 여부는 스코프 구성 상태 위에 함께 붙는 보조 상태다.
- 목록 상태는 기본 후보 / 검색 결과 / 결과 없음 중 하나만 동시에 성립해야 한다.
- root-only는 빈 상태가 아니라 현재 페이지 또는 현재 콜렉션 문맥이 제공하는 기본 적용 범위를 뜻한다.

## User-visible Feedback

- root-only 상태에서는 현재 범위가 비어 있는 것처럼 보이지 않고, 기본 적용 범위를 편집하는 상태로 읽혀야 한다.
- 단일 명시적 스코프 상태에서는 현재 기준 범위가 무엇인지 바로 읽혀야 한다.
- 다중 명시적 스코프 상태에서는 여러 기준 범위가 함께 포함된 상태라는 사실이 즉시 읽혀야 하며, 각 범위는 개별 조정 대상이 될 수 있어야 한다.
- 예외 포함 상태에서는 기준 범위와 예외가 같은 레벨의 후보처럼 보이지 않고, 예외가 기준 범위 아래에 붙은 보조 정보로 읽혀야 한다.
- 현재 포함된 범위는 "새로 추가 가능한 후보"와 동일한 시각 처리나 행동 처리로 보이면 안 된다.
- 현재 포함된 범위를 선택했을 때는 add 후보 선택과 같은 후속 동작으로 이어지면 안 된다.
- 동명 폴더가 여러 개면 이름 외 보조 위치 정보로 구분할 수 있어야 한다.

## Edge Cases / Failure Handling

- 스코프 편집창이 이미 열린 상태에서 다시 호출되면 현재 열린 편집 상태를 유지한다.
- 현재 범위가 매우 넓어도 처음부터 전체 파일시스템을 펼치지 않고 현재 맥락 중심으로 시작한다.
- 검색 결과가 없으면 결과 없음 상태와 복귀 가능한 다음 행동을 보여준다.
- 빠르게 검색어를 입력하고 지우는 경우에도 기본 후보, 검색 결과, 결과 없음 상태 전환이 뒤섞이면 안 된다.
- 이미 포함된 범위와 검색 결과 후보가 같은 이름을 가질 때도, 현재 포함 상태와 새 후보 상태가 혼동되면 안 된다.
- 예외가 존재하는 다중 범위 상태에서도 기준 범위 목록과 예외 목록의 위계가 무너지면 안 된다.

## Acceptance Criteria

- [ ] 사용자가 현재 스코프 요약 영역에서 해당 인터랙션을 호출하면, 시스템은 현재 콜렉션 범위를 편집하기 위한 스코프 편집창을 열어야 한다.
- [ ] 스코프 편집창이 열리면, 시스템은 현재 상태를 최소한 스코프 구성 상태(root-only / 단일 명시적 스코프 / 다중 명시적 스코프), 예외 상태(있음/없음), 목록 상태(기본 후보 / 검색 결과 / 결과 없음)로 구분해 표시해야 한다.
- [ ] 검색어를 입력하지 않은 상황에서, 스코프 편집창은 최근 방문 디렉토리나 즐겨찾기 등 기본 후보를 먼저 보여줘야 한다.
- [ ] 사용자가 검색어를 입력하면, 시스템은 기본 후보 상태를 검색 결과 상태로 전환해야 한다.
- [ ] 검색 결과가 없는 상황에서, 사용자가 검색을 수행하면, 시스템은 결과 없음 상태와 검색 수정 또는 기본 후보 복귀 가능성을 보여줘야 한다.
- [ ] 스코프 편집창이 열린 상황에서, 시스템은 현재 포함된 기준 범위와 예외 상태를 새 후보 목록과 구분되는 정보 영역으로 보여줘야 한다.
- [ ] 사용자가 현재 포함된 범위를 선택할 때, 시스템은 이를 새 범위 add 후보처럼 처리하지 않고 조정 / 제거 / 예외 관리가 가능한 현재 범위 항목으로 처리해야 한다.
- [ ] 예외가 존재하는 상황에서, 시스템은 예외 항목을 기준 범위와 같은 레벨의 후보처럼 보여주지 않고 기준 범위 아래의 보조 정보로 보여줘야 한다.

## Permissions / Dependencies

- `file_manager_window.content_pane.content_header.collection_filter_composer` 영역과 연결된 편집 흐름이어야 한다.
- 기본 후보 목록, 검색 결과, 결과 없음 상태가 서로 다른 목록 의미로 읽혀야 한다.
- 문서 이름에는 기존 "menu" 명칭이 남아 있지만, 실제 제품 해석은 스코프 편집창 기준으로 읽는다.
- Contract: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flow: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)

## Observability / Analytics

- 스코프 편집창 열기 진입
- 열릴 당시 범위 상태 유형
- 검색 진입 여부
- 결과 없음 상태 진입
- 현재 포함 범위 선택 vs 새 후보 선택 비율

## Related Interactions

- [RCL-001-add_directory_to_collection_scope](RCL-001-add_directory_to_collection_scope.md)
- [RCL-001-collapse_collection_filter_composer](RCL-001-collapse_collection_filter_composer.md)
- [RCL-001-exclude_directory_from_collection_scope](RCL-001-exclude_directory_from_collection_scope.md)
- [RCL-001-open_collection_filter_composer](RCL-001-open_collection_filter_composer.md)
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

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:119`
- Contracts: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flows: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)
