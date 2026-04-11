---
interaction_id: "EVM-002-set_entries_view_as_list_table"
interaction_type: "command"
feature: "Configure Entries View"
category_key: "EVM"
feature_id: "EVM-002"
status: "배포 완료"
summary: "Entries View를 리스트(테이블) 레이아웃으로 전환하고, listVisibleColumns 설정에 따라 컬럼 순서·표시를 반영"
related_region: "file_manager_window.content_pane"
menu: "View"
shortcut: "-"
---

# Set Entries View as List

## Intent

- 사용자가 동일한 Entry 데이터를 행과 컬럼 기반으로 빠르게 스캔하고 비교할 수 있어야 한다.
- 사용자가 설정한 List View 컬럼 구성이 전환 시에도 유지되어야 한다.

## Trigger / Entry Points

- 메뉴 `View`에서 `List`를 선택

## Preconditions

- 현재 Page가 Entries 목록을 표시하고 있는 상태

## Expected Outcome

- Entries가 한 행 단위로 표시되고, 현재 List View 컬럼 구성이 반영된다.
- List View의 컬럼 순서와 표시 여부는 listVisibleColumns 설정을 그대로 반영한다.
- 그룹핑이 적용된 상태라면, List View에서도 동일한 그룹 데이터가 그룹 헤더로 표현된다.

## State Changes

- Entries View의 레이아웃이 List로 설정된다.
- listVisibleColumns는 List View 컬럼 순서·표시의 정본이며, 이 인터랙션으로 임의로 초기화하거나 재정렬하지 않는다.
- listVisibleColumns가 아직 준비되지 않은 상황에서는, 기본값을 1회 구성한 뒤 이후에는 사용자 편집값을 유지한다.
- List View의 간격은 EntryListView 내부 규칙을 따른다.
    - contentInsets의 좌우 값은 0
    - intercellSpacing과 컬럼 간 간격은 보수적으로 줄어든 값

## User-visible Feedback

- Entries 표시가 즉시 리스트(테이블) 형태로 전환된다.
- 컬럼 헤더와 각 행의 셀 콘텐츠가 listVisibleColumns 설정에 맞게 다시 렌더링된다.

## Edge Cases / Failure Handling

- listVisibleColumns에 지원하지 않는 컬럼이 포함된 경우, 해당 컬럼은 무시하고 나머지를 표시한다.

## Acceptance Criteria

- [ ] 현재 페이지가 Entries를 정상적으로 표시하고 있을 때, 사용자가 해당 인터랙션을 호출하면, Entry
       구성이 리스트 레이아웃으로 전환되며 표시 속성은 기존 설정을 따름
- [ ] List View가 렌더링되는 상황에서, 컬럼 순서·표시 여부는 listVisibleColumns 설정을 따라야 한다.
- [ ] 그룹핑이 적용된 상황에서, List View로 전환해도 동일한 그룹 데이터가 그룹 헤더로 유지되어야 한다.
- [ ] List View가 렌더링되는 상황에서, 좌우 contentInsets가 0으로 적용되어 리스트 콘텐츠가 좌우 여백 없이 정렬되어야 한다.

## Permissions / Dependencies

- Entries 목록 데이터가 로드되어 있어야 한다.
- listVisibleColumns 설정을 조회할 수 있어야 한다.
- 그룹 헤더 표현을 위해 EntryArrangements 정보를 참조할 수 있어야 한다.

## Observability / Analytics

- Entries View 레이아웃 전환(리스트)
- List View 컬럼 설정(listVisibleColumns) 적용 여부

## Related Interactions

- `EVM-002-set_entries_view_as_icon_grid`
- `EVM-002-customize_list_view_column`
- `EVM-002-group_entries_by_property`
- `SET-003-adjust_text_size`
- `SET-003-adjust_icon_size`

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `24`
