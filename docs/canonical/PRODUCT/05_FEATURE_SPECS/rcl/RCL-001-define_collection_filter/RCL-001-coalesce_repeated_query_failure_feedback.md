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

- 동일한 실패 상태가 짧은 시간 안에 반복될 때 실패 피드백을 중복 누적하지 않고 노출 정책에 따라 합치거나 갱신함.
- `RCL-004`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- 사용자가 filter query 필드에 입력하거나 Enter로 제출할 때 호출된다.
- query 변환 결과가 돌아오거나 변환/실행 실패가 발생했을 때 호출된다.

## Preconditions

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 scope, query, condition draft를 읽고 갱신할 수 있어야 한다.

## Expected Outcome

- 짧은 시간 안에 반복되는 같은 conversion/execution failure를 새 toast로 계속 누적하지 않는다.
- 기존 `conversion_failure_feedback_visible` 또는 `execution_failure_feedback_visible` 상태를 최신 reason 중심으로 갱신한다.
- 실패 종류가 바뀌면 두 상태 간 전환을 명확히 남긴다.

## State Changes

- `conversion_failure_feedback_visible`과 `execution_failure_feedback_visible`을 읽고 같은 두 상태 중 하나를 다시 쓴다.
- conversion→execution 또는 execution→conversion 전환은 contract transition에 맞게 기록한다.
- coalesce는 포괄 실패 상태 같은 새 공통 상태를 만들지 않는다.

## User-visible Feedback

- 같은 실패는 같은 영역에서 최신 reason/시각/재시도 안내로 갱신한다.
- 다른 실패 종류로 바뀌면 사용자가 원인을 구분할 수 있게 메시지를 교체한다.

## Edge Cases / Failure Handling

- failure feedback 누적 때문에 Composer 편집 가능성이 가려지지 않아야 한다.
- 사용자가 query를 수정하면 다음 submit을 방해하지 않는다.
- 금지 상태인 포괄 실패 상태을 사용하지 않는다.

## Acceptance Criteria

- [ ] 같은 failure가 반복되면 실패 메시지는 중복 누적되지 않아야 한다.
- [ ] conversion failure와 execution failure는 서로 다른 상태로 구분되어야 한다.
- [ ] coalesce 후에도 사용자는 query를 수정하거나 다시 제출할 수 있어야 한다.

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
- Implementation references: `../voyager-app/docs/features/composer.md`, `../voyager-app/docs/features/entries-collections.md`, `../voyager-app/apps/macos/Voyager/Voyager/04_Features/Composer/Reducer/ComposerFeature.swift`, `../voyager-app/apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md), [collection_query_composition_flow.md](../flows/collection_query_composition_flow.md)
