---
interaction_id: "EVM-002-group_entries_by_property"
interaction_type: "command"
feature: "Configure Entries View"
category_key: "EVM"
feature_id: "EVM-002"
status: "배포 완료"
summary: "Entries View에서 선택한 Property를 기준으로 Entries를 그룹 섹션으로 묶어 같은 속성의 Entry 하나의 그룹 헤더 아래에 모아서 표시"
related_region: "file_manager_window.content_pane"
menu: "View"
shortcut: "-"
---

# Group Entries by Property

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- Entries View가 Icon View로 설정된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 선택한 프로퍼티 값이 일부 Entry에는 존재하지 않는 경우

## Acceptance Criteria

- [ ] 현재 Entries View가 Icon View일 때, 해당 인터랙션을 호출하면, 선택한 프로퍼티를 기준으로
      엔트리가 그룹 섹션으로 묶여 표시됨
- [ ] 특정 프로퍼티 그룹 섹션으로 묶여 표시될 때, 해당 프로퍼티가 없는 엔트리가 존재한다면, “미지정”
      그룹에 표시됨

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `27`
