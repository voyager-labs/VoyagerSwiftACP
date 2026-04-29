---
interaction_id: "RCL-004-show_query_conversion_failure_feedback"
interaction_type: "display"
feature: "Compose Collection Filter"
category_key: "RCL"
feature_id: "RCL-004"
status: "기획 완료"
summary: "자연어 쿼리 해석 단계에서 변환 실패가 발생했을 때 입력 흐름을 막지 않는 가벼운 실패 피드백을 표시해 반영되지 않은 이유를 이해할 수 있게 함"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Show Query Conversion Failure Feedback

## Intent

- query 해석 자체가 성립하지 않을 때, 사용자가 입력을 막힘 없이 수정·재시도할 수 있도록 Composer 문맥의 가벼운 실패 안내만 표시한다.

## Trigger / Entry Points

- [RCL-004-generate_filter_changes_from_query](RCL-004-generate_filter_changes_from_query.md)가 변환 실패로 종료되었을 때

## Preconditions

- Submit Collection Filter Query가 발생한 상태
- 현재 제출된 자연어 쿼리에 대한 응답이 유효한 최신 제출 흐름에 속한 상태
- Generate Filter Changes from Query가 변환 실패로 종료된 상태
- saved collection open alert 경로가 아닌 일반 Composer query 제출 흐름인 상태

## Expected Outcome

- 사용자는 왜 반영되지 않았는지 이해할 수 있는 가벼운 안내를 보되, 같은 입력 필드에서 즉시 수정·재시도할 수 있다.
- 실질 변경이 없거나 기존 조건 구성을 유지하는 결과는 이 인터랙션으로 승격되지 않는다.

## State Changes

- `query_submitting` -> `conversion_failure_feedback_visible`
    - 현재 query 제출 흐름이 변환 실패로 종료되면 가벼운 안내가 표시된다.
- `conversion_failure_feedback_visible` -> `editable`
    - 사용자가 Composer 문맥으로 돌아가 query 또는 condition 값을 다시 조정하기 시작하면 현재 feedback이 정리되고 편집 문맥이 유지된다.
- `conversion_failure_feedback_visible` -> `query_submitting`
    - 사용자가 다시 submit하면 새 최신 제출 흐름으로 전환된다.

## User-visible Feedback

- 피드백은 Composer 문맥 안의 가벼운 비차단 안내여야 한다.
- 사용자는 변환 실패와 실행 실패를 서로 다른 의미의 실패로 구분할 수 있어야 한다.

## Edge Cases / Failure Handling

- 오래된 제출 응답이 늦게 도착하는 경우
- 변환 실패 직후 사용자가 입력 내용을 수정해 다시 제출하는 경우
- 변환 실패와 실행 실패가 연속으로 발생하는 경우
- 실질적 필터 변경이 없는 경우에도 사용자 failure로 과도하게 확대하면 안 되는 경우
- 이전 feedback의 자동 해제가 새 feedback 표시 이후 늦게 도착하는 경우

## Acceptance Criteria

- [ ] Submit Collection Filter Query 이후 Generate Filter Changes from Query가 변환 실패로 종료되면, 시스템은 입력 흐름을 막지 않는 가벼운 실패 안내를 Collection Filter Composer 문맥에 표시해야 한다.
- [ ] 시스템은 변환 실패에 대응하는 고정 문구를 사용해 사용자가 왜 반영되지 않았는지 이해할 수 있게 해야 한다.
- [ ] 시스템은 피드백을 modal이나 blocking alert가 아니라 가벼운 인라인 안내로 표시해야 한다.
- [ ] 사용자는 feedback이 표시 중이어도 동일한 입력 필드에서 즉시 수정·재입력·재시도를 진행할 수 있어야 한다.
- [ ] 실질 변경이 없거나 기존 조건 구성을 유지하는 결과는 이 인터랙션의 표시 조건으로 취급되지 않아야 한다.
- [ ] 오래된 제출 결과나 늦게 도착한 자동 해제 이벤트가 현재 최신 제출 피드백 상태를 잘못 덮어쓰지 않아야 한다.

## Permissions / Dependencies

- 가장 최근 제출만 채택하는 규칙과 가벼운 인라인 안내 표시 규칙이 함께 유지되어야 한다.
- saved collection open failure alert 경로는 이 spec의 범위 밖이며 별도 기존 경로를 유지한다.

## Observability / Analytics

- 변환 실패 발생 횟수와 동일 실패 반복 여부를 실행 실패와 구분해 추적할 수 있어야 한다.
- feedback 표시 후 retry submit으로 이어졌는지 확인할 수 있어야 한다.

## Related Interactions

- [RCL-004-apply_all_generated_filter_suggestions](RCL-004-apply_all_generated_filter_suggestions.md)
- [RCL-004-apply_generated_filter_changes](RCL-004-apply_generated_filter_changes.md)
- [RCL-004-apply_generated_filter_suggestion](RCL-004-apply_generated_filter_suggestion.md)
- [RCL-004-coalesce_repeated_query_failure_feedback](RCL-004-coalesce_repeated_query_failure_feedback.md)
- [RCL-004-generate_filter_changes_from_query](RCL-004-generate_filter_changes_from_query.md)
- [RCL-004-generate_filter_suggestions_from_query](RCL-004-generate_filter_suggestions_from_query.md)
- [RCL-004-reject_all_generated_filter_suggestions](RCL-004-reject_all_generated_filter_suggestions.md)
- [RCL-004-reject_generated_filter_suggestion](RCL-004-reject_generated_filter_suggestion.md)
- [RCL-004-show_generated_filter_suggestions](RCL-004-show_generated_filter_suggestions.md)
- [RCL-004-show_query_execution_failure_feedback](RCL-004-show_query_execution_failure_feedback.md)
- [RCL-004-submit_collection_filter_query](RCL-004-submit_collection_filter_query.md)
- [RCL-004-type_collection_filter_query](RCL-004-type_collection_filter_query.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:110`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md)
