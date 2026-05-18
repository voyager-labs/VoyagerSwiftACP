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

- 검색 실행 또는 Helper/XPC 계층 오류로 적용이 실패했을 때 입력 흐름을 막지 않는 가벼운 실패 피드백을 표시해 실패 원인을 구분할 수 있게 함.
- `RCL-004`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- 사용자가 filter query 필드에 입력하거나 Enter로 제출할 때 호출된다.
- query 변환 결과가 돌아오거나 변환/실행 실패가 발생했을 때 호출된다.

## Preconditions

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 scope, query, condition draft를 읽고 갱신할 수 있어야 한다.

## Expected Outcome

- `query_submitting` 또는 `query_changes_generated` 이후 적용/검색 실행 경계에서 실패하면 `execution_failure_feedback_visible` 상태를 표시한다.
- conversion failure와 다른 reason으로 남겨 사용자가 해석 실패와 실행 실패를 구분할 수 있어야 한다.
- 부분 적용된 상태처럼 결과를 표시하지 않는다.
- 사용자는 query 수정 또는 재제출로 회복할 수 있다.

## State Changes

- `query_submitting` 또는 `query_changes_generated`를 읽고 `execution_failure_feedback_visible`을 쓴다.
- 이후 사용자가 query를 수정하면 `editable`로, 다시 제출하면 `query_submitting`으로 돌아갈 수 있다.
- conversion failure가 이어지는 경우 `conversion_failure_feedback_visible`과 구분해 coalesce한다.

## User-visible Feedback

- Composer 안에 실행 실패 reason을 non-blocking local feedback으로 표시한다.
- repeated same failure는 별도 toast 누적 없이 현재 feedback을 갱신한다.

## Edge Cases / Failure Handling

- execution failure를 conversion failure로 오분류하지 않는다.
- 실패한 실행 결과를 성공적으로 적용된 filter처럼 표시하지 않는다.
- 저장된 collection open failure는 이 query execution feedback이 아니라 RCL-002 management 경계에서 다룬다.

## Acceptance Criteria

- [ ] 실행 실패 시 `execution_failure_feedback_visible` 상태가 표시되어야 한다.
- [ ] execution failure는 conversion failure와 구분되어야 한다.
- [ ] 실패한 실행 결과는 부분 적용된 성공 상태처럼 표시되지 않아야 한다.

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
- [RCL-004-submit_collection_filter_query](RCL-004-submit_collection_filter_query.md)
- [RCL-004-type_collection_filter_query](RCL-004-type_collection_filter_query.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:111`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Implementation references: `../voyager-app/docs/features/composer.md`, `../voyager-app/docs/features/entries-collections.md`, `../voyager-app/apps/macos/Voyager/Voyager/04_Features/Composer/Reducer/ComposerFeature.swift`, `../voyager-app/apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md), [collection_query_composition_flow.md](../flows/collection_query_composition_flow.md)
