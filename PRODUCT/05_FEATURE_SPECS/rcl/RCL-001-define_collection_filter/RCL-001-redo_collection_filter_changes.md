---
interaction_id: "RCL-001-redo_collection_filter_changes"
interaction_type: "command"
feature: "Define Collection Filter"
category_key: "RCL"
feature_id: "RCL-001"
status: "배포 완료"
summary: "되돌린 필터 편집 작업을 한 단계 다시 적용해 되돌리기 전으로 복원"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "⌘⇧Z"
---

# Redo Collection Filter Changes

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- Generate Filter Changes from Query가 실행 중이지 않은 상태
- 필터 편집 되돌린 내역이 존재하는 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- -

## Acceptance Criteria

- [ ] 필터 편집을 되돌린 내역이 존재하는 상태일 때, 사용자가 해당 인터랙션을 호출하면, 되돌린 필터
      편집을 다시 적용하여 필터 상태를 갱신함

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `122`
