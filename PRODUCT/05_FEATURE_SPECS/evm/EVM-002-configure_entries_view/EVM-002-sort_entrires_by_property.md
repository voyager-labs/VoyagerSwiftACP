---
interaction_id: "EVM-002-sort_entrires_by_property"
interaction_type: "command"
feature: "Configure Entries View"
category_key: "EVM"
feature_id: "EVM-002"
status: "배포 완료"
summary: "Entries View에서 선택한 Property를 기준으로 Entries 표시 순서를 정렬함"
related_region: "file_manager_window.content_pane"
menu: "View"
shortcut: "-"
---

# Sort Entrires by Property

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- Entries View가 List / Icon / Column VIew로 설정된 상태
- 정렬 가능한 프로퍼티가 정의된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

-   -

## Acceptance Criteria

- [ ] 현재 페이지가 Entries를 정상적으로 표시하고 있을 때, 사용자가 해당 인터랙션을 호출하면, 선택한
      프로퍼티 기준으로 Entries가 오름/내림차순으로 재정렬됨
- [ ] 선택한 프로퍼티로 정렬을 유지할 때, 엔트리 간 동일 값이 존재한다면, 기본적으로 이름을 2차 정렬
      규칙으로 적용함

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `28`
