---
interaction_id: "RCL-003-evaluate_text_query_condition_lexically"
interaction_type: "background"
feature: "Retrieve Entries with Filters"
category_key: "RCL"
feature_id: "RCL-003"
status: "아이디어"
summary: "텍스트 쿼리 컨디션을 대상으로 키워드 매칭∙스코어링으로 평가해 키워드 매칭 신호를 생성"
related_region: "-"
menu: "-"
shortcut: "-"
---

# Evaluate Text Query Condition Lexically

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 텍스트 쿼리 컨디션 정의가 필터에 포함된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 키워드 매칭을 수행할 인덱스가 준비되지 않았거나 사용 불가한 상태인 경우
- 콜렉션 스코프가 넓거나 결정론 필터로 후보가 충분히 줄지 않아 평가 대상 엔트리 수가 과도하게 커지는
  경우

## Acceptance Criteria

- [ ] 후보 엔트리 집합이 산출된 상태일 때, 텍스트 쿼리 컨디션 정의가 필터에 포함된 상태라면, 키워드
      매칭과 스코어링을 수행해 엔트리별 키워드 매칭 신호를 생성함
- [ ] 키워드 매칭 신호를 생성할 때, 키워드 매칭을 수행할 자체 인덱스가 준비되지 않았거나 사용 불가한
      상태라면, OS 인덱싱 기반 검색으로 폴백해 키워드 매칭 신호를 생성함
- [ ] 키워드 매칭 신호를 생성할 때, 평가 대상 엔트리 수가 과도하게 커진다면, 성능 보호 정책을 적용해
      평가 범위를 제한한 뒤 키워드 매칭 신호를 생성함

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- [RCL-003-apply_deterministic_filters](RCL-003-apply_deterministic_filters.md)
- [RCL-003-combine_hybrid_scores](RCL-003-combine_hybrid_scores.md)
- [RCL-003-evaluate_text_query_condition_semantically](RCL-003-evaluate_text_query_condition_semantically.md)
- [RCL-003-execute_filtered_collection_retrieval](RCL-003-execute_filtered_collection_retrieval.md)
- [RCL-003-indicate_collection_results_staleness](RCL-003-indicate_collection_results_staleness.md)
- [RCL-003-invalidate_closed_collection_staleness_on_external_change](RCL-003-invalidate_closed_collection_staleness_on_external_change.md)
- [RCL-003-mark_collection_results_as_stale](RCL-003-mark_collection_results_as_stale.md)
- [RCL-003-mark_open_collection_as_stale_on_external_change](RCL-003-mark_open_collection_as_stale_on_external_change.md)
- [RCL-003-rank_entries_by_relevance](RCL-003-rank_entries_by_relevance.md)
- [RCL-003-refresh_collection_results](RCL-003-refresh_collection_results.md)
- [RCL-003-refresh_stale_collection_results_on_reopen](RCL-003-refresh_stale_collection_results_on_reopen.md)
- [RCL-003-request_collection_results_refresh](RCL-003-request_collection_results_refresh.md)
- [RCL-003-update_collection_results_on_filter_change](RCL-003-update_collection_results_on_filter_change.md)
## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `158`
