---
interaction_id: "EVM-002-customize_list_view_column"
interaction_type: "input"
feature: "Configure Entries View"
category_key: "EVM"
feature_id: "EVM-002"
status: "준비 완료"
summary: "Entries View가 리스트 레이아웃일 때, Entry 이름, 확장자, 크기, 날짜 등 표시할 속성 컬럼의 종류, 표시 여부, 순서를 편집"
related_region: "file_manager_window.content_pane"
menu: "-"
shortcut: "-"
---

# Customize List View Column

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- Entries View가 List View로 설정된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 필수적으로 남겨야 하는 기본 컬럼까지 모두 숨기려 하는 경우

## Acceptance Criteria

- [ ] Entries View가 List View로 설정된 상태일 때, 사용자가 컬럼 종류·표시 여부·순서를 편집하면,
      리스트가 해당 설정대로 즉시 갱신됨
- [ ] 컬럼 편집을 수행하는 상태일 때, 사용자가 모든 컬럼을 숨기려 하면, 최소 이름 컬럼은 항상 유지됨
- [ ] 동일 탭 세션이 유지되는 상태일 때, 사용자가 컬럼 설정을 변경하면, 사용자 설정이 해당 탭
      세션에서 지속 유지됨

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `30`
