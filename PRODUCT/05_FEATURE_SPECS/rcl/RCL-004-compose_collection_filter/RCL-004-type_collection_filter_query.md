---
interaction_id: "RCL-004-type_collection_filter_query"
interaction_type: "input"
feature: "Compose Collection Filter"
category_key: "RCL"
feature_id: "RCL-004"
status: "배포 완료"
summary: "필터 쿼리 텍스트필드에 쿼리를 입력해 입력값을 갱신"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Type Collection Filter Query

## Intent

- Collection Filter Composer의 입력창 내용을 갱신해 사용자가 새 자연어 필터 요청을 준비하거나, 실패 피드백 이후 현재 query를 바로 수정할 수 있게 한다.

## Trigger / Entry Points

- 사용자가 Collection Filter Composer 텍스트필드에 포커스를 두고 입력을 시작했을 때
- 변환 실패 또는 실행 실패 피드백 이후 같은 Composer 문맥에서 query를 다시 조정하기 시작했을 때

## Preconditions

- Collection Filter Composer가 열린 상태
- 입력창 내용을 수정할 수 있는 현재 편집 문맥이 유지되고 있는 상태

## Expected Outcome

- 현재 입력창 내용이 최신 입력 기준으로 갱신된다.
- 입력 자체만으로 query submit이 자동 발생하지 않으며, 이후 submit 여부는 별도 인터랙션에서 결정된다.
- 실패 피드백이 표시 중이었다면 사용자가 query를 다시 조정하기 시작할 때 편집 문맥이 유지된다.

## State Changes

- `editable` -> `editable`
    - 사용자가 입력창 내용을 계속 수정해도 Composer는 같은 편집 문맥을 유지한다.
- `conversion_failure_feedback_visible` -> `editable`
    - 사용자가 query를 다시 조정하기 시작하면 기존 conversion failure feedback은 정리되고 편집 문맥이 유지된다.
- `execution_failure_feedback_visible` -> `editable`
    - 사용자가 query를 다시 조정하기 시작하면 기존 execution failure feedback은 정리되고 편집 문맥이 유지된다.

## User-visible Feedback

- 사용자는 텍스트필드 입력 중 별도 blocking 없이 현재 query를 자유롭게 수정할 수 있어야 한다.
- failure feedback 직후에도 동일한 입력 필드에서 바로 query를 다시 다듬을 수 있어야 한다.

## Edge Cases / Failure Handling

- 오래된 제출 결과가 늦게 도착해도 현재 입력창 내용을 덮어쓰면 안 되는 경우
- failure feedback이 표시 중인 상태에서 사용자가 즉시 query를 다시 조정하는 경우
- 입력 중 이전 해석 결과나 자동 해제 이벤트가 늦게 도착하는 경우

## Acceptance Criteria

- [ ] 사용자가 Collection Filter Composer 텍스트필드에 입력하면, 시스템은 현재 입력창 내용을 최신 입력 기준으로 갱신해야 한다.
- [ ] 사용자가 query를 입력하는 행위 자체는 자동 submit을 의미하지 않아야 하며, submit은 별도 인터랙션에서만 시작되어야 한다.
- [ ] conversion failure 또는 execution failure feedback 직후 사용자가 query를 다시 조정하기 시작하면, 시스템은 해당 feedback을 정리하고 `editable` 편집 문맥을 유지해야 한다.
- [ ] 오래된 제출 결과나 늦게 도착한 피드백 정리 이벤트가 현재 입력창 내용을 잘못 되돌리거나 덮어쓰지 않아야 한다.

## Permissions / Dependencies

- 가장 최근 제출만 채택하는 규칙과 현재 입력창 내용을 보존하는 규칙이 함께 유지되어야 한다.
- 입력창 편집은 [RCL-004-submit_collection_filter_query](RCL-004-submit_collection_filter_query.md) 이전 준비 단계로 동작해야 한다.

## Observability / Analytics

- 입력창 수정 이후 재제출로 이어졌는지 확인할 수 있어야 한다.
- failure feedback 이후 query re-entry가 얼마나 자주 발생하는지 구분해 추적할 수 있어야 한다.

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
- [RCL-004-show_query_conversion_failure_feedback](RCL-004-show_query_conversion_failure_feedback.md)
- [RCL-004-show_query_execution_failure_feedback](RCL-004-show_query_execution_failure_feedback.md)
- [RCL-004-submit_collection_filter_query](RCL-004-submit_collection_filter_query.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:106`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md)
