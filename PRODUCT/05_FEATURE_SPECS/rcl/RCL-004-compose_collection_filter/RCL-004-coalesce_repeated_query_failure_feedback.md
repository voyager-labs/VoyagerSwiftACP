---
interaction_id: "RCL-004-coalesce_repeated_query_failure_feedback"
interaction_type: "background"
feature: "Compose Collection Filter"
category_key: "RCL"
feature_id: "RCL-004"
status: "기획 완료"
summary: "동일한 실패 상태가 짧은 시간 안에 반복될 때 실패 피드백을 중복 누적하지 않고 노출 정책에 따라 합치거나 갱신함"
related_region: "-"
menu: "-"
shortcut: "-"
---

# Coalesce Repeated Query Failure Feedback

## Intent

- 동일한 변환 실패 또는 실행 실패가 짧은 시간 안에 반복될 때, Composer 문맥의 실패 안내가 과하게 쌓이지 않도록 중복 노출을 합치거나 최신 의미로만 갱신한다.

## Trigger / Entry Points

- [RCL-004-show_query_conversion_failure_feedback](RCL-004-show_query_conversion_failure_feedback.md) 또는 [RCL-004-show_query_execution_failure_feedback](RCL-004-show_query_execution_failure_feedback.md)가 새 실패 안내를 표시하려 할 때

## Preconditions

- 현재 실패 안내가 이미 표시 중인 상태
- 짧은 시간 안에 동일하거나 의미가 다른 새 실패가 다시 도착한 상태

## Expected Outcome

- 동일 메시지 반복은 하나의 안내로 유지되고, 의미가 다른 실패만 최신 의미 기준으로 교체된다.
- 중복 억제는 사용자의 재시도 권한을 막지 않는다.

## State Changes

- `conversion_failure_feedback_visible` -> `conversion_failure_feedback_visible`
    - 동일 변환 실패가 반복되면 새 toast를 추가하지 않고 기존 표시를 유지한다.
- `execution_failure_feedback_visible` -> `execution_failure_feedback_visible`
    - 동일 실행 실패가 반복되면 새 toast를 추가하지 않고 기존 표시를 유지한다.
- `conversion_failure_feedback_visible` -> `execution_failure_feedback_visible`
    - 의미가 다른 최신 실패가 도착하면 마지막 실패 의미 기준으로 갱신한다.
- `execution_failure_feedback_visible` -> `conversion_failure_feedback_visible`
    - 마지막 실패 의미가 변환 실패로 바뀌면 해당 피드백으로 갱신한다.

## User-visible Feedback

- 사용자는 같은 실패가 반복되어도 toast가 연속 적층되지 않는다고 느껴야 한다.
- 마지막 실패 의미가 달라졌을 때만 피드백 문구가 갱신되어야 한다.

## Edge Cases / Failure Handling

- 오래된 request 응답이 더 늦게 도착하는 경우
- 동일한 실패가 매우 짧은 간격으로 여러 번 발생하는 경우
- 변환 실패와 실행 실패가 교차 발생하는 경우
- 이전 자동 해제 타이머가 더 새로운 feedback 이후 늦게 도착하는 경우

## Acceptance Criteria

- [ ] 동일한 변환 실패 또는 동일한 실행 실패가 짧은 시간 안에 반복되면, 시스템은 새 피드백을 적층하지 않고 기존 피드백을 유지해야 한다.
- [ ] 시스템은 중복 억제 기준을 실패 의미 단위로 적용해야 하며, 변환 실패와 실행 실패를 하나의 일반 실패로 뭉개지 않아야 한다.
- [ ] 의미가 다른 최신 실패가 도착하면, 시스템은 마지막 실패 의미 기준으로 피드백을 교체하거나 갱신해야 한다.
- [ ] 오래된 request 응답이나 늦게 도착한 자동 해제 이벤트가 더 새로운 feedback을 잘못 제거하지 않아야 한다.
- [ ] 중복 억제는 사용자가 Composer 편집 문맥으로 돌아가 query 또는 조건 값을 다시 조정하거나 다시 제출하는 흐름을 막지 않아야 한다.

## Permissions / Dependencies

- 실패 의미 비교와 가장 최근 제출만 채택하는 규칙이 함께 유지되어야 한다.
- 피드백 자동 해제 정책은 중복 억제 후에도 불필요하게 다시 시작되거나 연장되지 않아야 한다.

## Observability / Analytics

- 동일 실패 중복 억제 횟수와 유형 교체 횟수를 분리해 추적할 수 있어야 한다.
- 중복 억제 대상이 변환 실패인지 실행 실패인지 구분 가능해야 한다.

## Related Interactions

- [RCL-004-apply_all_generated_filter_suggestions](RCL-004-apply_all_generated_filter_suggestions.md)
- [RCL-004-apply_generated_filter_changes](RCL-004-apply_generated_filter_changes.md)
- [RCL-004-apply_generated_filter_suggestion](RCL-004-apply_generated_filter_suggestion.md)
- [RCL-004-generate_filter_changes_from_query](RCL-004-generate_filter_changes_from_query.md)
- [RCL-004-generate_filter_suggestions_from_query](RCL-004-generate_filter_suggestions_from_query.md)
- [RCL-004-reject_all_generated_filter_suggestions](RCL-004-reject_all_generated_filter_suggestions.md)
- [RCL-004-reject_generated_filter_suggestion](RCL-004-reject_generated_filter_suggestion.md)
- [RCL-004-show_generated_filter_suggestions](RCL-004-show_generated_filter_suggestions.md)
- [RCL-004-show_query_conversion_failure_feedback](RCL-004-show_query_conversion_failure_feedback.md)
- [RCL-004-show_query_execution_failure_feedback](RCL-004-show_query_execution_failure_feedback.md)
- [RCL-004-submit_collection_filter_query](RCL-004-submit_collection_filter_query.md)
- [RCL-004-type_collection_filter_query](RCL-004-type_collection_filter_query.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:112`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md)
