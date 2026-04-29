---
interaction_id: "RCL-004-generate_filter_changes_from_query"
interaction_type: "background"
feature: "Compose Collection Filter"
category_key: "RCL"
feature_id: "RCL-004"
status: "배포 완료"
summary: "제출된 쿼리를 해석해 현재 필터에 반영할 구조화 조건 변경안을 산출해 반환"
related_region: "-"
menu: "-"
shortcut: "-"
---

# Generate Filter Changes from Query

## Intent

- 제출된 query를 현재 필터 조건 문맥에 맞는 구조화된 변경 결과로 해석해, 사용자가 바로 반영 가능한 조건 구성을 얻도록 한다.

## Trigger / Entry Points

- [RCL-004-submit_collection_filter_query](RCL-004-submit_collection_filter_query.md) 이후 가장 최근 제출 흐름이 시작되었을 때

## Preconditions

- Submit Collection Filter Query가 발생한 상태
- 현재 처리 중인 요청이 해당 Composer 문맥의 가장 최근 제출인 상태

## Expected Outcome

- 시스템이 제출된 query를 해석해 적용 가능한 조건 변경 결과, 실질 변경 없음, 기존 조건 구성 유지, 또는 실패 결과 중 하나로 정리한다.
- 정상 계열 결과는 변환 실패와 분리되어 이후 반영 여부를 결정할 수 있어야 한다.

## State Changes

- `query_submitting` -> `query_changes_generated`
    - 시스템이 적용 가능한 조건 변경 결과를 만들면 현재 요청을 성공 결과 상태로 전환한다.
- `query_submitting` -> `query_changes_generated`
    - 실질 변경이 없는 결과여도 실패가 아니라 성공 결과 상태로 귀결된다.
- `query_submitting` -> `query_changes_generated`
    - 기존 조건 구성을 유지하는 편이 더 적절하다고 판단되더라도 성공 결과 상태로 귀결된다.
- `query_submitting` -> `conversion_failure_feedback_visible`
    - 자연어 해석 자체가 성립하지 않으면 변환 실패 feedback 경로로 넘긴다.
- `query_submitting` -> `execution_failure_feedback_visible`
    - 해석 이후 실행 단계 또는 보조 실행 계층에서 실패가 확인되면 실행 실패 피드백 경로로 넘긴다.

## User-visible Feedback

- 이 백그라운드 단계 자체가 별도 모달을 만들지는 않지만, 이후 정상 반영 / 실질 변경 없음 / 기존 조건 구성 유지 / 실패 분기가 사용자에게 일관된 다음 상태를 제공해야 한다.

## Edge Cases / Failure Handling

- 만들어진 변경 내용이 비어 있지만 현재 조건 구성을 유지하는 편이 맞는 경우
- 기존 조건 구성을 유지하는 결과가 사용자에게 변환 실패처럼 보이면 안 되는 경우
- 더 오래된 제출 결과가 늦게 도착하는 경우
- 조건 변경 결과 생성은 성공했지만 반영 이후 실행 실패로 이어지는 경우

## Acceptance Criteria

- [ ] Submit Collection Filter Query가 발생한 상황에서, 시스템이 query를 해석하면 현재 필터 조건 구성에 적용 가능한 구조화 변경 결과를 산출해야 한다.
- [ ] 시스템이 실질 변경이 없는 결과를 얻었을 때, 이를 실패가 아니라 정상 종료된 결과로 유지해야 한다.
- [ ] 시스템이 내부 대체 규칙이나 직전 유효 조건 구성을 유지하는 쪽을 선택했을 때, 이를 변환 실패로 승격하지 않고 정상 계열 결과로 유지해야 한다.
- [ ] 자연어 해석 자체가 성립하지 않으면, 시스템은 conversion failure 경로로 분기해야 한다.
- [ ] 해석 이후 실행 단계 또는 보조 실행 계층 문제가 발생하면, 시스템은 실행 실패 경로로 분기해야 한다.
- [ ] 더 오래된 제출 결과가 늦게 도착하더라도, 시스템은 가장 최근 제출 상태를 덮어쓰지 않아야 한다.

## Permissions / Dependencies

- 현재 Composer 문맥의 가장 최근 제출 정보와 기존 조건 구성 기준점을 함께 참조할 수 있어야 한다.
- 조건 변경 결과는 과거 제안 목록 형태가 아니라 바로 반영 가능한 현재 모델이어야 한다.

## Observability / Analytics

- query 해석 결과를 정상 반영 / 실질 변경 없음 / 기존 조건 구성 유지 / 변환 실패 / 실행 실패로 구분해 기록할 수 있어야 한다.
- 가장 최근 제출만 채택되었는지와 오래된 응답이 무시되었는지 추적할 수 있어야 한다.

## Related Interactions

- [RCL-004-submit_collection_filter_query](RCL-004-submit_collection_filter_query.md)
- [RCL-004-apply_generated_filter_changes](RCL-004-apply_generated_filter_changes.md)
- [RCL-004-show_query_conversion_failure_feedback](RCL-004-show_query_conversion_failure_feedback.md)
- [RCL-004-show_query_execution_failure_feedback](RCL-004-show_query_execution_failure_feedback.md)
- [RCL-004-coalesce_repeated_query_failure_feedback](RCL-004-coalesce_repeated_query_failure_feedback.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:108`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md)
