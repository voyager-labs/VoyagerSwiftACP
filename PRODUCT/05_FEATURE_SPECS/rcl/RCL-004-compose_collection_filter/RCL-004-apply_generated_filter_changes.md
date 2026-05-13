---
interaction_id: "RCL-004-apply_generated_filter_changes"
interaction_type: "background"
feature: "Compose Collection Filter"
category_key: "RCL"
feature_id: "RCL-004"
status: "배포 완료"
summary: "생성된 필터 변경안을 현재 필터 정의에 일괄 반영"
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

- 생성된 필터 변경안을 현재 필터 정의에 일괄 반영.
- 입력 query는 trim된 값으로 처리하고 빈 query는 불필요한 변환 요청을 만들지 않아야 한다.
- 변환 결과는 suggestion 대기 상태가 아니라 현재 filter draft에 일괄 반영하는 경로를 기본으로 삼는다.
- 동일 failure가 반복되면 피드백을 누적하지 않고 갱신 또는 병합한다.

## State Changes

- query draft, submittedSearchFilters, active request id, feedback toast 상태를 갱신한다.
- 변환 성공 시 returned appliedFilters 또는 structured filter changes를 현재 Composer state로 반영한다.
- conversion failure와 execution failure는 서로 다른 failure reason으로 남긴다.

## User-visible Feedback

- query 입력 중에는 field 값을 즉시 반영한다.
- 변환/실행 실패는 Composer 흐름을 막지 않는 가벼운 피드백으로 보여준다.
- 반복 failure는 같은 영역에서 최신 reason 중심으로 갱신한다.
- background interaction은 별도 화면을 만들기보다 연결된 display/command interaction이 읽을 상태를 갱신한다.

## Edge Cases / Failure Handling

- 빈 query submit은 네트워크 요청 없이 무시한다.
- 변환은 성공했지만 적용 가능한 조건이 없으면 현재 filter를 임의로 비우지 않는다.
- 취소된 suggestion 기반 interaction은 현재 기본 흐름에서 노출하지 않는다.

## Acceptance Criteria

- [ ] query를 입력하면 Composer query draft가 갱신되어야 한다.
- [ ] query를 제출하면 구조화 filter 변경안 생성과 적용이 순서대로 진행되어야 한다.
- [ ] 동일 failure가 짧은 시간 안에 반복되면 실패 메시지는 중복 누적되지 않아야 한다.

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

- [RCL-004-type_collection_filter_query](RCL-004-type_collection_filter_query.md)
- [RCL-004-submit_collection_filter_query](RCL-004-submit_collection_filter_query.md)
- [RCL-004-generate_filter_changes_from_query](RCL-004-generate_filter_changes_from_query.md)
- [RCL-004-show_query_conversion_failure_feedback](RCL-004-show_query_conversion_failure_feedback.md)
- [RCL-004-show_query_execution_failure_feedback](RCL-004-show_query_execution_failure_feedback.md)
- [RCL-004-coalesce_repeated_query_failure_feedback](RCL-004-coalesce_repeated_query_failure_feedback.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:109`
- Flows: [collection_query_composition_flow.md](../flows/collection_query_composition_flow.md)
- Implementation references: `../voyager-app/docs/features/composer.md`, `../voyager-app/docs/features/entries-collections.md`, `../voyager-app/apps/macos/Voyager/Voyager/04_Features/Composer/Reducer/ComposerFeature.swift`, `../voyager-app/apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`
