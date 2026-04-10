---
interaction_id: "RCL-001-change_collection_condition_operator"
interaction_type: "input"
feature: "Define Collection Filter"
category_key: "RCL"
feature_id: "RCL-001"
status: "배포 완료"
summary: "선택한 컨디션의 연산자를 다른 연산자로 변경"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Change Collection Condition Operator

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- Generate Filter Changes from Query가 실행 중이지 않은 상태
- 편집 대상 컨디션이 존재하는 상태
- 해당 컨디션의 프로퍼티가 설정된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 오퍼레이터 변경으로 기존 값이 무효가 되는 경우

## Acceptance Criteria

- [ ] 해당 컨디션이 오퍼레이터 편집 상태일 때, 사용자가 해당 인터랙션을 호출하면, 해당 컨디션의
      오퍼레이터가 갱신됨
- [ ] 사용자가 오퍼레이터를 변경했을 때, 기존 값이 무효가 된다면, 값을 초기화함

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `118`
