---
interaction_id: "RCL-001-change_collection_condition_value"
interaction_type: "input"
feature: "Define Collection Filter"
category_key: "RCL"
feature_id: "RCL-001"
status: "배포 완료"
summary: "선택한 컨디션의 비교 값 또는 범위를 편집해 해당 조건이 만족하는 엔트리 집합을 조정"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Change Collection Condition Value

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- Generate Filter Changes from Query가 실행 중이지 않은 상태
- 편집 대상 컨디션이 존재하는 상태
- 해당 컨디션의 프로퍼티와 오퍼레이터가 설정된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 범위 입력이 필요한데 한쪽 값만 확정되는 경우

## Acceptance Criteria

- [ ] 해당 컨디션이 값 편집 상태일 때, 사용자가 해당 인터랙션을 호출하면, 해당 컨디션의 값이 갱신됨
- [ ] 설정된 오퍼레이터에 따라 범위 입력이 필요할 때, 한쪽 값만 입력이 되었다면, 해당 컨디션은
      미완성 상태로 표시됨

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `119`
