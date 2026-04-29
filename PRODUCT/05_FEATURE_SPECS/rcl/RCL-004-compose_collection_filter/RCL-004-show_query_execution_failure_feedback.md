---
interaction_id: "RCL-004-show_query_execution_failure_feedback"
interaction_type: "display"
feature: "Compose Collection Filter"
category_key: "RCL"
feature_id: "RCL-004"
status: "기획 완료"
summary: "검색 실행 단계 오류로 반영이 실패했을 때 입력 흐름을 막지 않는 가벼운 실패 피드백을 표시해 실패 원인을 구분할 수 있게 함"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Show Query Execution Failure Feedback

## Intent

- 입력 해석은 성립했지만 반영 이후 실행 단계가 실패했을 때, 변환 실패와 구분되는 가벼운 실패 안내를 Composer 문맥에 보여준다.

## Trigger / Entry Points

- [RCL-004-generate_filter_changes_from_query](RCL-004-generate_filter_changes_from_query.md) 또는 [RCL-004-apply_generated_filter_changes](RCL-004-apply_generated_filter_changes.md) 이후 실행 실패가 확인되었을 때

## Preconditions

- Submit Collection Filter Query가 발생한 상태
- 현재 입력 해석 또는 반영 흐름에 대한 응답이 최신 제출 흐름에 속한 상태
- 변환 실패가 아니라 실행 단계 실패가 확인된 상태
- saved collection open failure alert 경로가 아닌 일반 Composer query 제출 흐름인 상태

## Expected Outcome

- 사용자는 변환 실패와 다른 의미의 실행 실패 안내를 보고, 현재 입력 문맥에서 즉시 다시 수정하거나 재시도할 수 있다.

## State Changes

- `query_submitting` -> `execution_failure_feedback_visible`
    - query 제출 흐름이 실행 실패로 종료되면 가벼운 실행 실패 안내를 표시한다.
- `query_changes_generated` -> `execution_failure_feedback_visible`
    - 조건 변경 결과 생성 이후 반영 또는 실행 단계에서 실패가 나면 같은 실패 경로로 합류한다.
- `execution_failure_feedback_visible` -> `editable`
    - 사용자가 Composer 문맥으로 돌아가 query 또는 condition 값을 다시 조정하기 시작하면 현재 feedback이 정리되고 편집 상태가 유지된다.
- `execution_failure_feedback_visible` -> `query_submitting`
    - 사용자가 같은 필드에서 즉시 다시 submit하면 새 최신 제출이 시작된다.

## User-visible Feedback

- 피드백은 Collection Filter Composer 상단 문맥의 가벼운 비차단 안내여야 한다.
- 변환 실패와 구분되는 별도 고정 문구를 사용해야 한다.

## Edge Cases / Failure Handling

- 변환은 성공했지만 반영 이후 검색 실행이 실패하는 경우
- 서로 다른 실행 계층 오류가 같은 사용자 메시지 정책을 공유하는 경우
- 오래된 제출 응답이 늦게 도착하는 경우
- failure feedback 표시 중 사용자가 연속 submit을 반복하는 경우
- 이전 feedback의 자동 해제가 새 feedback 표시 이후 늦게 도착하는 경우

## Acceptance Criteria

- [ ] Submit Collection Filter Query 이후 실행 단계 오류가 발생하면, 시스템은 입력 흐름을 막지 않는 가벼운 실행 실패 안내를 Collection Filter Composer 문맥에 표시해야 한다.
- [ ] 시스템은 실행 실패에 대응하는 고정 문구를 사용해 변환 실패와 구분되는 의미를 전달해야 한다.
- [ ] 사용자는 feedback이 표시 중이어도 즉시 입력을 수정하거나 다시 submit할 수 있어야 한다.
- [ ] 조건 변경 결과 생성 성공 뒤 반영 또는 실행 단계에서 실패한 경우도 이 인터랙션의 범위로 흡수되어야 한다.
- [ ] 오래된 제출 결과나 늦게 도착한 자동 해제 이벤트가 현재 최신 제출 피드백 상태를 잘못 덮어쓰지 않아야 한다.
- [ ] 저장된 콜렉션 다시 열기 실패는 이 인터랙션의 가벼운 인라인 안내로 다루지 않고 기존 alert 경로를 유지해야 한다.

## Permissions / Dependencies

- 가장 최근 제출만 채택하는 규칙과 실행 실패 분류 규칙이 함께 유지되어야 한다.
- 실행 실패는 저장된 콜렉션을 다시 여는 경고 경로와 분리되어야 한다.

## Observability / Analytics

- 실행 실패 발생 횟수와 반영 이후 실패 여부를 변환 실패와 구분해 추적할 수 있어야 한다.
- 반복 실패가 중복 억제 정책으로 합쳐졌는지 확인할 수 있어야 한다.

## Related Interactions

- [RCL-004-submit_collection_filter_query](RCL-004-submit_collection_filter_query.md)
- [RCL-004-generate_filter_changes_from_query](RCL-004-generate_filter_changes_from_query.md)
- [RCL-004-apply_generated_filter_changes](RCL-004-apply_generated_filter_changes.md)
- [RCL-004-show_query_conversion_failure_feedback](RCL-004-show_query_conversion_failure_feedback.md)
- [RCL-004-coalesce_repeated_query_failure_feedback](RCL-004-coalesce_repeated_query_failure_feedback.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:111`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md)
