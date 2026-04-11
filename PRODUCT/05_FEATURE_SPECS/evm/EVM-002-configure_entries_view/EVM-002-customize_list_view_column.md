---
interaction_id: "EVM-002-customize_list_view_column"
interaction_type: "input"
feature: "Configure Entries View"
category_key: "EVM"
feature_id: "EVM-002"
status: "준비 완료"
summary: "List View에서 listVisibleColumns를 편집해 컬럼 표시 여부와 순서를 설정"
related_region: "file_manager_window.content_pane"
menu: "-"
shortcut: "-"
---

# Customize List View Column

## Intent

- 사용자가 List View에서 보고 싶은 컬럼만 남기고, 필요한 순서로 재배치해 빠르게 스캔할 수 있어야 한다.
- List View 컬럼의 순서·표시 여부는 listVisibleColumns가 정본으로 관리되어야 한다.

## Trigger / Entry Points

- List View의 컬럼 편집 UI에서 진입(예: 컬럼 헤더 영역의 편집 메뉴)

## Preconditions

- Entries View가 List View로 설정된 상태

## Expected Outcome

- 사용자가 List View 컬럼의 표시 여부와 순서를 편집하면, 즉시 리스트에 반영된다.

## State Changes

- listVisibleColumns가 사용자의 편집 결과로 갱신된다.
- listVisibleColumns는 List View 컬럼 순서·표시의 정본이며, 현재 열려 있는 List View는 해당 값으로 즉시 다시 렌더링된다.

## User-visible Feedback

- 컬럼 헤더와 행의 컬럼 구성이 즉시 변경된다.

## Edge Cases / Failure Handling

- 필수 컬럼 정책에 어긋나는 편집 요청이 들어오면, 시스템이 허용 가능한 범위로 보정해 반영한다.
- 지원하지 않는 컬럼을 포함한 편집 요청이 들어오면, 시스템이 해당 항목을 무시하고 가능한 설정만 반영한다.

## Acceptance Criteria

- [ ] Entries View가 List View로 설정된 상태일 때, 사용자가 컬럼 종류·표시 여부·순서를 편집하면,
       리스트가 해당 설정대로 즉시 갱신됨
- [ ] List View 상태에서, 사용자가 컬럼 설정을 변경하면, listVisibleColumns가 갱신되어 동일한 List View 렌더링의 정본으로 적용되어야 한다.
- [ ] 컬럼 편집 요청이 현재 정책에 맞지 않는 상황에서, 시스템은 허용 가능한 범위의 컬럼 구성만 반영해야 한다.

## Permissions / Dependencies

- List View가 활성화되어 있어야 한다.
- listVisibleColumns 설정을 저장하고 불러올 수 있어야 한다.

## Observability / Analytics

- List View 컬럼 편집 진입
- listVisibleColumns 변경(컬럼 순서, 표시 여부)

## Related Interactions

- `EVM-002-set_entries_view_as_list_table`
- `EVM-002-set_entries_view_as_icon_grid`

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `31`
