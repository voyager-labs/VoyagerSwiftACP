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

- 필터 쿼리 텍스트필드에 쿼리를 입력해 입력값을 갱신.
- `RCL-004`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- 사용자가 filter query 필드에 입력하거나 Enter로 제출할 때 호출된다.
- query 변환 결과가 돌아오거나 변환/실행 실패가 발생했을 때 호출된다.

## Preconditions

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 scope, query, condition draft를 읽고 갱신할 수 있어야 한다.

## Expected Outcome

- 사용자의 입력은 `query_input` draft로 유지되며, 입력 중 Composer는 `editable` 상태를 유지한다.
- 기존 `conversion_failure_feedback_visible` 또는 `execution_failure_feedback_visible` 피드백이 있더라도 사용자는 같은 필드에서 query를 수정할 수 있어야 한다.
- 입력만으로는 `generated_change_set`을 만들지 않고, Enter 제출이 발생할 때만 `query_submitting` 전환을 준비한다.
- 취소된 suggestion 기반 상태인 suggestion 목록 상태 또는 suggestion 대기 상태은 노출하지 않는다.

## State Changes

- `editable`을 읽고 다시 `editable`로 쓴다.
- 이전 `conversion_failure_feedback_visible` 또는 `execution_failure_feedback_visible` 상태에서 사용자가 입력을 수정하면 피드백은 방해 요소가 아니라 수정 가능한 이전 결과로 취급한다.
- `query_input` draft는 최신 입력값으로 갱신하지만 active request id는 제출 전까지 변경하지 않는다.

## User-visible Feedback

- query 입력 중에는 field 값을 즉시 반영한다.
- 이전 conversion/execution failure 피드백은 입력 수정 가능성을 막지 않고, 최신 입력과 함께 정리될 수 있다.

## Edge Cases / Failure Handling

- 빈 query draft는 제출 전까지 오류로 표시하지 않는다.
- 입력 중에는 네트워크 요청을 만들지 않는다.
- 금지 상태인 suggestion 목록 상태, suggestion 대기 상태, 포괄 실패 상태 문구를 사용자 상태로 노출하지 않는다.

## Acceptance Criteria

- [ ] query를 입력하면 Composer query draft가 갱신되어야 한다.
- [ ] 이전 failure 피드백이 보여도 사용자는 같은 필드에서 query를 수정할 수 있어야 한다.
- [ ] 입력만으로는 변환 요청이나 suggestion 대기 상태가 생성되지 않아야 한다.

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
- [RCL-004-submit_collection_filter_query](RCL-004-submit_collection_filter_query.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:106`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Implementation references: `../voyager-app/docs/features/composer.md`, `../voyager-app/docs/features/entries-collections.md`, `../voyager-app/apps/macos/Voyager/Voyager/04_Features/Composer/Reducer/ComposerFeature.swift`, `../voyager-app/apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md), [collection_query_composition_flow.md](../flows/collection_query_composition_flow.md)
