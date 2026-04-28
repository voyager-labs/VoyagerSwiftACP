---
interaction_id: "RCL-003-indicate_collection_results_staleness"
interaction_type: "display"
feature: "Retrieve Entries with Filters"
category_key: "RCL"
feature_id: "RCL-003"
status: "아이디어"
summary: "현재 콜렉션 결과가 stale 상태일 때 collection title affordance 영역에 상태를 표시해 사용자가 최신성이 보장되지 않음을 인지할 수 있게 함"
related_region: "file_manager_window.content_pane.content_header"
menu: "-"
shortcut: "-"
---

# Indicate Collection Results Staleness

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 현재 콜렉션 결과가 stale 상태로 판단된 상태
- 사용자가 현재 콜렉션 페이지를 보고 있는 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- stale 상태지만 아직 usable snapshot 결과를 표시 중인 경우
- stale가 해제되기 전 사용자가 수동 refresh를 여러 번 시도하는 경우
- dirty 표시와 stale 표시가 함께 존재하는 경우
- 현재 브랜치에서는 stale 표시 UI affordance가 아직 미구현이라 이후 UI task에서 구체화되어야 하는
  경우

## Acceptance Criteria

- [ ] 현재 콜렉션 결과가 stale 상태이면, 시스템은 사용자가 freshness가 보장되지 않음을 인지할 수
      있는 stale 표시를 노출하도록 함
- [ ] 시스템은 stale 표시를 dirty 표시와 구분해, save 가능 여부와 최신성 여부가 다른 의미임을 유지함
- [ ] usable snapshot 결과를 표시 중인 경우라도 stale 상태라면, 시스템은 사용자가 현재 결과를 최신
      결과로 오인하지 않도록 stale 상태를 유지해 전달함
- [ ] refresh 성공 시 stale가 해제되면, 시스템은 stale 표시를 제거하거나 최신 상태에 맞게 갱신함

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
- Source line: `153`
