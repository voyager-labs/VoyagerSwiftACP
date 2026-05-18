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

- 제출된 쿼리를 해석해 현재 필터에 반영할 구조화 조건 변경안을 산출해 반환.
- `RCL-004`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- 사용자가 filter query 필드에 입력하거나 Enter로 제출할 때 호출된다.
- query 변환 결과가 돌아오거나 변환/실행 실패가 발생했을 때 호출된다.

## Preconditions

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 scope, query, condition draft를 읽고 갱신할 수 있어야 한다.

## Expected Outcome

- `query_submitting` 상태의 `query_input`을 해석해 현재 filter definition에 맞는 `generated_change_set`을 만든다.
- 실질 변경이 없으면 `unchanged_result`로 성공 처리하고 실패 피드백을 표시하지 않는다.
- 새 해석 대신 직전 유효 definition 또는 내부 fallback rule을 사용하면 `fallback_reuse`로 성공 처리한다.
- 해석 실패는 `conversion_failure_feedback_visible`로, 적용/검색 경계 실패는 `execution_failure_feedback_visible`로 분리한다.

## State Changes

- `query_submitting`을 읽고 `query_changes_generated`, `conversion_failure_feedback_visible`, `execution_failure_feedback_visible` 중 하나를 쓴다.
- `generated_change_set`, `unchanged_result`, `fallback_reuse`는 모두 conversion failure와 구분된다.
- 기존 condition은 새 결과가 명시적으로 대체하지 않는 한 보존한다.

## User-visible Feedback

- 생성 성공, 변경 없음, fallback reuse는 실패 피드백이 아니라 성공 계열 결과로 해석한다.
- conversion failure는 Composer 내부의 non-blocking 피드백으로 표시한다.

## Edge Cases / Failure Handling

- 해석 가능한 조건이 없어도 현재 filter를 임의로 비우지 않는다.
- 동일 query에 대해 반복되는 실패는 별도 toast를 계속 만들지 않고 coalesce 대상이 된다.
- 포괄 실패 상태 같은 포괄 실패 상태로 합치지 않는다.

## Acceptance Criteria

- [ ] query 해석 성공 시 `query_changes_generated` 상태가 기록되어야 한다.
- [ ] `unchanged_result`와 `fallback_reuse`는 실패로 표시되지 않아야 한다.
- [ ] conversion failure와 execution failure는 서로 다른 상태로 남아야 한다.

## Permissions / Dependencies

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 scope, query, condition draft를 읽고 갱신할 수 있어야 한다.
- 이 interaction은 특정 UI region 없이 background/domain state를 갱신한다.

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
- [RCL-004-generate_filter_suggestions_from_query](RCL-004-generate_filter_suggestions_from_query.md)
- [RCL-004-reject_all_generated_filter_suggestions](RCL-004-reject_all_generated_filter_suggestions.md)
- [RCL-004-reject_generated_filter_suggestion](RCL-004-reject_generated_filter_suggestion.md)
- [RCL-004-show_generated_filter_suggestions](RCL-004-show_generated_filter_suggestions.md)
- [RCL-004-show_query_conversion_failure_feedback](RCL-004-show_query_conversion_failure_feedback.md)
- [RCL-004-show_query_execution_failure_feedback](RCL-004-show_query_execution_failure_feedback.md)
- [RCL-004-submit_collection_filter_query](RCL-004-submit_collection_filter_query.md)
- [RCL-004-type_collection_filter_query](RCL-004-type_collection_filter_query.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:108`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Implementation references: `../voyager-app/docs/features/composer.md`, `../voyager-app/docs/features/entries-collections.md`, `../voyager-app/apps/macos/Voyager/Voyager/04_Features/Composer/Reducer/ComposerFeature.swift`, `../voyager-app/apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md), [collection_query_composition_flow.md](../flows/collection_query_composition_flow.md)
