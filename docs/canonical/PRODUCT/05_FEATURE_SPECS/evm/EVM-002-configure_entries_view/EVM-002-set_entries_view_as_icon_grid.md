---
interaction_id: "EVM-002-set_entries_view_as_icon_grid"
interaction_type: "command"
feature: "Configure Entries View"
category_key: "EVM"
feature_id: "EVM-002"
status: "배포 완료"
summary: "Entries View를 아이콘 그리드 레이아웃으로 전환해 동일한 Entry 데이터를 그리드 방식으로 표시"
related_region: "file_manager_window.content_pane"
menu: "View"
shortcut: "-"
---

# Set Entries View as Icon

## Intent

- 사용자가 동일한 Entry 데이터를 아이콘 중심의 그리드 레이아웃으로 빠르게 탐색할 수 있어야 한다.
- List View와 동일한 데이터 의미(정렬, 그룹핑, 태그 색상 규칙)를 유지한 채 렌더링만 그리드로 바꿔야 한다.

## Trigger / Entry Points

- 메뉴 `View`에서 `Icon`을 선택

## Preconditions

- 현재 Page가 Entries 목록을 표시하고 있는 상태

## Expected Outcome

- Entries가 아이콘(썸네일) 중심의 그리드로 표시된다.
- 동일한 Entry 데이터에 대해 List View와 같은 정렬 의미를 유지한다.
- 그룹핑이 적용된 상태라면, 그리드에서도 동일한 그룹 데이터가 그룹 헤더로 표현된다.
- 그리드 항목의 태그 색상 규칙은 동일한 규칙에 따라 적용된다.
- 그리드의 아이콘 크기와 텍스트 크기는 사용자 설정에 저장된 해당 뷰의 설정값을 사용한다.

## State Changes

- Entries View의 레이아웃이 Icon으로 설정된다.
- 정렬 설정은 전환 시에도 유지된다.

## User-visible Feedback

- Entries 표시가 즉시 아이콘 그리드 형태로 전환된다.

## Edge Cases / Failure Handling

- 그룹핑 대상 프로퍼티 값이 일부 Entry에 없는 경우, 해당 Entry는 “미지정” 그룹에 포함된다.
- 그리드 아이콘 또는 텍스트 크기 설정값이 범위를 벗어난 경우, 시스템이 유효 범위로 보정해 표시한다.

## Acceptance Criteria

- [ ] 현재 페이지가 Entries를 정상적으로 표시하고 있을 때, 사용자가 해당 인터랙션을 호출하면, Entry
       구성이 그리드 레이아웃으로 전환되며 정렬은 기존 설정을 따름
- [ ] 그룹핑이 적용된 상황에서, Icon으로 전환해도 동일한 그룹 데이터가 그룹 헤더로 유지되어야 한다.
- [ ] Entry에 태그가 있는 상황에서, 그리드 항목의 태그 색상 규칙은 동일한 규칙에 따라 적용되어야 한다.

## Permissions / Dependencies

- Entries 목록 데이터가 로드되어 있어야 한다.
- 그룹 헤더 및 태그 색상 규칙에 필요한 정보를 참조할 수 있어야 한다.

## Observability / Analytics

- Entries View 레이아웃 전환(아이콘 그리드)

## Related Interactions

- `EVM-002-set_entries_view_as_list_table`
- `EVM-002-group_entries_by_property`
- `SET-003-adjust_text_size`
- `SET-003-adjust_icon_size`

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `25`
