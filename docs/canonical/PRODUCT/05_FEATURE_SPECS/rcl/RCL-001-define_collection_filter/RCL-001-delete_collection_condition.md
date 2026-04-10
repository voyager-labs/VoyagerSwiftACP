---
interaction_id: "RCL-001-delete_collection_condition"
interaction_type: "command"
feature: "Define Collection Filter"
category_key: "RCL"
feature_id: "RCL-001"
status: "배포 완료"
summary: "선택한 컨디션을 필터에서 제거"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "⌫"
---

# Delete Collection Condition

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- Generate Filter Changes from Query가 실행 중이지 않은 상태
- 삭제 대상 컨디션이 존재하는 상태
- 삭제 대상 컨디션이 지정된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 마지막 남은 컨디션을 제거하는 경우

## Acceptance Criteria

- [ ] Collection Filter Composer가 열린 상태일 때, 사용자가 해당 인터랙션을 호출하면, 해당 컨디션이
      필터에서 제거됨
- [ ] 사용자가 컨디션을 제거하려할 때, 해당 컨디션이 마지막 남은 컨디션이라면, 콜렉션은 컨디션 없는
      상태가 됨

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `120`
