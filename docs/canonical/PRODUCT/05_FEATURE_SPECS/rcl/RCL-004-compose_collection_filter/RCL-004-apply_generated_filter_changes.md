---
interaction_id: "RCL-004-apply_generated_filter_changes"
interaction_type: "background"
feature: "Compose Collection Filter"
category_key: "RCL"
feature_id: "RCL-004"
status: "배포 완료"
summary: "생성된 필터 변경안을 현재 필터 조건 구성에 반영"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Apply Generated Filter Changes

## Intent

- 생성된 필터 변경안을 현재 필터 정의에 일괄 반영.
- `RCL-004`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- 사용자가 filter query 필드에 입력하거나 Enter로 제출할 때 호출된다.
- query 변환 결과가 돌아오거나 변환/실행 실패가 발생했을 때 호출된다.

## Preconditions

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 scope, query, condition draft를 읽고 갱신할 수 있어야 한다.

## Expected Outcome

- `query_changes_generated` 상태의 `generated_change_set`을 현재 filter draft에 일괄 반영한다.
- 반영 결과가 유효한 filter definition이면 Composer는 `editable`을 유지하면서 저장 가능한 `save_ready` 상태로 이어진다.
- `unchanged_result`나 `fallback_reuse`인 경우에도 현재 유효 filter definition을 보존하고 failure로 표시하지 않는다.
- 적용 후 결과 갱신은 RCL-003 retrieval 흐름으로 넘긴다.

## State Changes

- `query_changes_generated`를 읽고 `editable`과 `save_ready`를 쓴다.
- 적용된 condition set과 query draft는 현재 filter definition의 저장 기준점으로 사용될 수 있다.
- 적용 중 execution failure가 발생하면 이 interaction이 아니라 `RCL-004-show_query_execution_failure_feedback`이 `execution_failure_feedback_visible`을 소유한다.

## User-visible Feedback

- 변경 반영 자체는 별도 suggestion UI 없이 Composer state로 나타난다.
- 적용 가능한 변경이 없으면 실패가 아니라 변경 없음 성공으로 표시한다.
- background interaction은 별도 화면을 만들기보다 연결된 display/command interaction이 읽을 상태를 갱신한다.

## Edge Cases / Failure Handling

- `generated_change_set`이 현재 filter와 동일하면 `unchanged_result`로 처리한다.
- fallback으로 기존 유효 definition을 재사용하면 `fallback_reuse`로 처리한다.
- 금지 상태인 suggestion 목록 상태 또는 suggestion 대기 상태을 만들지 않는다.

## Acceptance Criteria

- [ ] 생성된 filter 변경안은 suggestion 대기 없이 현재 filter draft에 반영되어야 한다.
- [ ] 유효한 변경 반영 후 저장 가능한 경우 `save_ready`로 이어져야 한다.
- [ ] 변경 없음/fallback reuse는 실패 피드백으로 표시되지 않아야 한다.

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
- [RCL-004-type_collection_filter_query](RCL-004-type_collection_filter_query.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:109`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Implementation references: `../voyager-app/docs/features/composer.md`, `../voyager-app/docs/features/entries-collections.md`, `../voyager-app/apps/macos/Voyager/Voyager/04_Features/Composer/Reducer/ComposerFeature.swift`, `../voyager-app/apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md), [collection_query_composition_flow.md](../flows/collection_query_composition_flow.md)
