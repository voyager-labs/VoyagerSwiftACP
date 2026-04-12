---
interaction_id: "RCL-001-collapse_collection_filter_composer"
interaction_type: "command"
feature: "Define Collection Filter"
category_key: "RCL"
feature_id: "RCL-001"
status: "배포 완료"
summary: "Collection Filter Composer를 닫아 페이지 타이틀 바 기본 상태로 전환하며, 미저장 변경은 유지"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "ESC"
---

# Collapse Collection Filter Composer

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- Collection Filter Composer가 열린 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 미저장 필터 변경이 존재하는 경우
- 필터 편집 중 호출되는 경우
- 필터 생성 파이프라인이 실행 중인 상태에서 호출되는 경우

## Acceptance Criteria

- [ ] Collection Filter Composer가 열린 상태일 때, 사용자가 해당 인터랙션을 호출하면, Collection
      Filter Composer가 닫히고 페이지 타이틀 바 기본 상태로 전환함
- [ ] 미저장 필터 변경이 존재하는 상태일 때, 사용자가 해당 인터랙션을 호출하면, 변경을 폐기하지 않고
      유지하며, 타이틀바에 미저장 상태를 표시함
- [ ] 필터 편집 중인 상태일 때, 사용자가 해당 인터랙션을 호출하면, 진행 중인 편집 UI와 함께
      Collection Filter Composer를 닫음
- [ ] 필터 생성 파이프라인이 실행 중인 상태에서 사용자가 해당 인터랙션을 호출하면, 파이프라인은
      중단하지 않고 진행 상태를 유지함

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `102`
