---
interaction_id: "RCL-003-refresh_collection_results"
interaction_type: "command"
feature: "Retrieve Entries with Filters"
category_key: "RCL"
feature_id: "RCL-003"
status: "배포 완료"
summary: "현재 설정된 필터를 기준으로 엔트리 검색을 수동 실행해 최신 결과 목록으로 갱신"
related_region: "-"
menu: "-"
shortcut: "-"
---

# Refresh Collection Results

## Intent

- 현재 설정된 필터를 기준으로 엔트리 검색을 수동 실행해 최신 결과 목록으로 갱신.
- `RCL-003`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- query submit, condition 변경, scope 변경, 수동 refresh 입력이 검색 결과 재계산을 요구할 때 호출된다.
- 열린 collection 또는 다시 열린 collection이 stale 상태일 때 refresh 정책을 실행한다.

## Preconditions

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 검색 API에 전달할 `SearchFiltersPayload`를 만들 수 있어야 한다.

## Expected Outcome

- 현재 설정된 필터를 기준으로 엔트리 검색을 수동 실행해 최신 결과 목록으로 갱신.
- `SearchFiltersPayload`에 포함 가능한 active condition만 전송되어야 한다.
- 서버가 반환한 `appliedFilters`는 UI state의 정규화 기준으로 다시 반영되어야 한다.
- 진행 중인 search/applyFilters 요청은 cancellation id로 마지막 요청만 유효하게 관리되어야 한다.

## State Changes

- isLoadingSearch, isLoadingFilters, isFilteringInFlight, active request id, lastFiltersResponse를 갱신한다.
- registry 기반 key resolution으로 canonical, legacy, unknown condition 상태를 정리한다.
- stale 상태는 즉시 결과를 폐기하는 대신 refresh 필요 상태로 기록한다.

## User-visible Feedback

- 검색/필터 적용 중에는 loading 상태를 표시하고 중복 실행을 막는다.
- unknown property key는 제거하지 않고 비활성 condition으로 남겨 사용자가 원인을 볼 수 있게 한다.
- stale 결과는 최신성이 보장되지 않음을 표시하고 refresh 진입점을 제공한다.

## Edge Cases / Failure Handling

- 조건이 비어 있거나 값 인코딩에 실패한 condition은 payload에서 제외한다.
- submit은 진행 중인 filter 요청을 취소하고, filter apply는 진행 중인 search 요청을 취소한다.
- 서버 응답에 적용 불가능한 조건이 있으면 appliedFilters 기준으로 UI를 보정한다.
- 명령 실행 중 실패하면 대상 상태를 부분 적용된 것처럼 표시하지 않는다.

## Acceptance Criteria

- [ ] active condition과 scope가 있는 상황에서 refresh를 실행하면 검색 API가 호출되고 결과 state가 갱신되어야 한다.
- [ ] legacy property key가 appliedFilters로 돌아오면 canonical key로 보정되어야 한다.
- [ ] 모든 condition이 제거되면 filter apply 요청은 스킵되고 in-flight filter 요청은 취소되어야 한다.

## Permissions / Dependencies

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 검색 API에 전달할 `SearchFiltersPayload`를 만들 수 있어야 한다.
- 이 interaction은 특정 UI region 없이 background/domain state를 갱신한다.

## Observability / Analytics

- interaction 실행 여부
- 요청/적용 성공 여부
- 실패 reason과 recovery action
- 마지막으로 적용된 filter snapshot

## Related Interactions

- [RCL-003-execute_filtered_collection_retrieval](RCL-003-execute_filtered_collection_retrieval.md)
- [RCL-003-update_collection_results_on_filter_change](RCL-003-update_collection_results_on_filter_change.md)
- [RCL-003-apply_deterministic_filters](RCL-003-apply_deterministic_filters.md)
- [RCL-003-mark_collection_results_as_stale](RCL-003-mark_collection_results_as_stale.md)
- [RCL-003-refresh_stale_collection_results_on_reopen](RCL-003-refresh_stale_collection_results_on_reopen.md)
- [RCL-003-invalidate_closed_collection_staleness_on_external_change](RCL-003-invalidate_closed_collection_staleness_on_external_change.md)
- [RCL-003-mark_open_collection_as_stale_on_external_change](RCL-003-mark_open_collection_as_stale_on_external_change.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:151`
- Flows: [collection_retrieval_flow.md](../flows/collection_retrieval_flow.md)
- Implementation references: `../voyager-app/docs/features/composer.md`, `../voyager-app/docs/features/entries-collections.md`, `../voyager-app/apps/macos/Voyager/Voyager/04_Features/Composer/Reducer/ComposerFeature.swift`, `../voyager-app/apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`
