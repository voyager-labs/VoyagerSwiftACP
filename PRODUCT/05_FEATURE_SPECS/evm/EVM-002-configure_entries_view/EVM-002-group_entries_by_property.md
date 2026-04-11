---
interaction_id: "EVM-002-group_entries_by_property"
interaction_type: "command"
feature: "Configure Entries View"
category_key: "EVM"
feature_id: "EVM-002"
status: "배포 완료"
summary: "Entries View에서 선택한 Property 값으로 Entries를 그룹화해 섹션 헤더 아래에 표시하며, 그룹 라벨·색상 규칙은 EntryArrangements를 따름"
related_region: "file_manager_window.content_pane"
menu: "View"
shortcut: "-"
---

# Group Entries by Property

## Intent

- 사용자가 많은 Entries를 특정 Property 값 기준으로 묶어 빠르게 훑고, 그룹 단위로 탐색할 수 있어야 한다.
- List View와 Icon View가 동일한 그룹 데이터 의미와 표현 규칙을 공유해야 한다.

## Trigger / Entry Points

- 메뉴 `View`에서 그룹핑 기준(Property)을 선택

## Preconditions

- Entries View가 List View 또는 Icon View로 표시 중인 상태

## Expected Outcome

- 선택한 Property의 값으로 Entries가 그룹 섹션으로 나뉘어 표시된다.
- 각 그룹은 그룹 헤더를 가지며, 그룹 라벨과 색상 표현은 EntryArrangements가 소유한 규칙을 따른다.
- Property 값이 없는 Entry는 “미지정” 그룹에 포함된다.
- 동일한 그룹 데이터는 List View와 Icon View에서 일관되게 해석되어 표시된다.

## State Changes

- Entries View의 그룹핑 기준이 선택한 Property로 갱신된다.
- 현재 열려 있는 List View와 Icon View는 동일한 그룹핑 상태를 반영해 다시 렌더링된다.

## User-visible Feedback

- 그룹 헤더가 추가되고, Entries가 그룹 섹션 아래로 재배치되어 표시된다.

## Edge Cases / Failure Handling

- 선택한 Property 값이 일부 Entry에 없는 경우, 해당 Entry는 “미지정” 그룹에 표시한다.
- 선택한 Property를 그룹핑 기준으로 해석할 수 없는 경우, 기존 그룹핑 상태를 유지하고 사용자에게 변경 불가 상태를 안내한다.

## Acceptance Criteria

- [ ] 현재 Entries View가 List View 또는 Icon View인 상황에서, 해당 인터랙션을 호출하면, 선택한 프로퍼티를 기준으로 Entries가 그룹 섹션으로 묶여 표시되어야 한다.
- [ ] 특정 프로퍼티 그룹 섹션으로 묶여 표시될 때, 해당 프로퍼티가 없는 엔트리가 존재한다면, “미지정”
       그룹에 표시됨
- [ ] 그룹 섹션이 표시되는 상황에서, 그룹 헤더의 라벨·색상 표현은 EntryArrangements 규칙을 따라야 한다.
- [ ] 동일한 그룹핑이 적용된 상황에서, List View와 Icon View는 동일한 그룹 데이터 의미로 렌더링되어야 한다.

## Permissions / Dependencies

- Entries 목록 데이터가 로드되어 있어야 한다.
- 그룹 라벨·색상 및 태그 색상 규칙을 위해 EntryArrangements 정보를 참조할 수 있어야 한다.

## Observability / Analytics

- 그룹핑 기준 변경(프로퍼티)

## Related Interactions

- `EVM-002-set_entries_view_as_list_table`
- `EVM-002-set_entries_view_as_icon_grid`
- `EVM-002-sort_entrires_by_property`

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `28`
