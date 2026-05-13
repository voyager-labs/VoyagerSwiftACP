---
interaction_id: "RCL-004-submit_collection_filter_query"
interaction_type: "command"
feature: "Compose Collection Filter"
category_key: "RCL"
feature_id: "RCL-004"
status: "배포 완료"
summary: "텍스트필드에 입력된 쿼리를 제출해 필터 생성 파이프라인을 시작"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "⏎"
---

# Submit Collection Filter Query

## Intent

- 텍스트필드에 입력된 쿼리를 제출해 필터 생성 파이프라인을 시작.
- `RCL-004`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- 사용자가 filter query 필드에 입력하거나 Enter로 제출할 때 호출된다.
- query 변환 결과가 돌아오거나 변환/실행 실패가 발생했을 때 호출된다.

## Preconditions

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 scope, query, condition draft를 읽고 갱신할 수 있어야 한다.

## Expected Outcome

- trim된 `query_input`을 현재 scope/condition draft와 함께 제출하고, 가장 최근 제출만 유효한 `query_submitting` 상태를 시작한다.
- 빈 query는 불필요한 변환 요청을 만들지 않는다.
- 제출은 suggestion 대기 상태가 아니라 `generated_change_set` 산출 또는 실패 피드백 상태로 이어진다.
- 이전 `conversion_failure_feedback_visible` 또는 `execution_failure_feedback_visible` 피드백은 새 제출 기준으로 교체될 수 있어야 한다.

## State Changes

- `editable`, `condition_value_incomplete`, `conversion_failure_feedback_visible`, `execution_failure_feedback_visible`을 읽고 `query_submitting`을 쓴다.
- active request id는 최신 제출 기준으로 갱신하며, 이전 요청 결과가 늦게 도착해도 현재 Composer state를 덮어쓰지 않는다.
- `query_input`은 제출 snapshot으로 고정하지만 사용자는 실패 후 다시 `editable`로 돌아와 수정할 수 있다.

## User-visible Feedback

- 제출 중에는 query가 처리 중임을 가볍게 표시한다.
- 이전 failure feedback이 남아 있으면 최신 `query_submitting` 상태 기준으로 정리한다.

## Edge Cases / Failure Handling

- 빈 query submit은 네트워크 요청 없이 무시한다.
- 이전 요청보다 늦게 도착한 결과는 최신 제출 기준이 아니면 반영하지 않는다.
- 취소된 suggestion 기반 interaction은 현재 기본 흐름에서 노출하지 않는다.

## Acceptance Criteria

- [ ] query를 제출하면 `query_submitting` 상태가 시작되어야 한다.
- [ ] 이전 요청 결과가 늦게 도착해도 최신 제출 결과를 덮어쓰지 않아야 한다.
- [ ] 빈 query submit은 변환 요청을 만들지 않아야 한다.

## Permissions / Dependencies

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 scope, query, condition draft를 읽고 갱신할 수 있어야 한다.
- 관련 UI region: `file_manager_window.content_pane.content_header.collection_filter_composer`

## Observability / Analytics

- interaction 실행 여부
- 요청/적용 성공 여부
- 실패 reason과 recovery action
- 마지막으로 적용된 filter snapshot

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
- [RCL-004-type_collection_filter_query](RCL-004-type_collection_filter_query.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:107`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Implementation references: `../voyager-app/docs/features/composer.md`, `../voyager-app/docs/features/entries-collections.md`, `../voyager-app/apps/macos/Voyager/Voyager/04_Features/Composer/Reducer/ComposerFeature.swift`, `../voyager-app/apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md), [collection_query_composition_flow.md](../flows/collection_query_composition_flow.md)
