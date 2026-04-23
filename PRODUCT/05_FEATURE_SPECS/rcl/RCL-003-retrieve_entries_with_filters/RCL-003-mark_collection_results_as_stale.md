---
interaction_id: "RCL-003-mark_collection_results_as_stale"
interaction_type: "background"
feature: "Retrieve Entries with Filters"
category_key: "RCL"
feature_id: "RCL-003"
status: "기획 완료"
summary: "파일시스템 변경 등으로 현재 결과의 최신성이 깨졌을 때 콜렉션 결과를 stale 상태로 전환해 후속 refresh 필요를 기록"
related_region: "-"
menu: "-"
shortcut: "-"
---

# Mark Collection Results as Stale

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 저장된 또는 열린 콜렉션 결과가 현재 표시되거나 복원 가능한 상태
- 결과 최신성이 깨졌다고 판단할 수 있는 조건이 발생한 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- dirty 상태와 stale 상태가 동시에 존재해 서로 다른 의미를 구분해야 하는 경우
- 현재 열린 collection이 아니더라도 저장된 closed collection record는 invalidation될 수 있는 경우
- root scope(/) collection이 모든 descendant path 변경에 반응해야 하는 경우
- snapshot은 존재하지만 최신성만 의심되는 경우
- stale 상태가 되어도 현재 결과를 즉시 폐기하거나 자동 재검색하지 않는 경우
- refresh 실패 이후 stale 상태를 계속 유지해야 하는 경우

## Acceptance Criteria

- [ ] 파일시스템 변경 등으로 현재 결과의 최신성이 깨졌다고 판단되면, 시스템은 열린 collection 결과를
      stale 상태로 전환할 수 있음
- [ ] 시스템은 dirty와 stale를 같은 의미로 취급하지 않고, save 가능 여부는 dirty 기준으로만 판단함
- [ ] stale 상태가 되더라도 시스템은 현재 snapshot 또는 현재 결과를 즉시 폐기하지 않고 후속 refresh
      정책과 분리해 유지할 수 있음
- [ ] collection route에서는 파일시스템 변경이 발생해도 즉시 reload/search를 다시 실행하지 않고
      stale 표시/기록으로 처리함
- [ ] 현재 열려 있지 않은 저장된 collection에 대해서도, future reopen freshness 판단을 위해
      staleness record를 갱신할 수 있음
- [ ] refresh가 실패하면, 시스템은 stale 상태를 해제하지 않고 그대로 유지함

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- [RCL-003-apply_deterministic_filters](RCL-003-apply_deterministic_filters.md)
- [RCL-003-combine_hybrid_scores](RCL-003-combine_hybrid_scores.md)
- [RCL-003-evaluate_text_query_condition_lexically](RCL-003-evaluate_text_query_condition_lexically.md)
- [RCL-003-evaluate_text_query_condition_semantically](RCL-003-evaluate_text_query_condition_semantically.md)
- [RCL-003-execute_filtered_collection_retrieval](RCL-003-execute_filtered_collection_retrieval.md)
- [RCL-003-indicate_collection_results_staleness](RCL-003-indicate_collection_results_staleness.md)
- [RCL-003-invalidate_closed_collection_staleness_on_external_change](RCL-003-invalidate_closed_collection_staleness_on_external_change.md)
- [RCL-003-mark_open_collection_as_stale_on_external_change](RCL-003-mark_open_collection_as_stale_on_external_change.md)
- [RCL-003-rank_entries_by_relevance](RCL-003-rank_entries_by_relevance.md)
- [RCL-003-refresh_collection_results](RCL-003-refresh_collection_results.md)
- [RCL-003-refresh_stale_collection_results_on_reopen](RCL-003-refresh_stale_collection_results_on_reopen.md)
- [RCL-003-request_collection_results_refresh](RCL-003-request_collection_results_refresh.md)
- [RCL-003-update_collection_results_on_filter_change](RCL-003-update_collection_results_on_filter_change.md)
## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `152`
