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

- 자연어 제출 결과로 나온 구조화된 조건 변경 내용을 현재 필터 조건 구성에 한 번에 반영해, 사용자가 바로 이해하고 이어서 다듬을 수 있는 상태로 만든다.

## Trigger / Entry Points

- [RCL-004-generate_filter_changes_from_query](RCL-004-generate_filter_changes_from_query.md)가 success 계열 결과를 반환했을 때

## Preconditions

- Generate Filter Changes from Query 결과가 success 계열로 확정된 상태
- 현재 요청이 여전히 가장 최근 제출에 해당하는 상태

## Expected Outcome

- 구조화된 조건 변경 내용이 현재 필터 조건 구성에 반영되고, 사용자는 곧바로 추가 수정이나 저장을 이어갈 수 있다.
- 실질적으로 바뀔 내용이 없거나 기존 조건 구성을 유지하는 편이 더 적절한 경우에는 실패 피드백 없이 현재 조건 구성을 그대로 유지한다.

## State Changes

- `query_changes_generated` -> `editable`
    - 시스템이 구조화된 조건 변경 결과 반영을 마치면 Composer가 다시 수동 편집 가능한 상태로 돌아간다.
- `query_changes_generated` -> `save_ready`
    - 적용 결과가 마지막 저장 기준점과 달라 유효한 미저장 조건 구성이 되면 저장 가능한 상태가 된다.
- `query_changes_generated` -> `editable`
    - 실질 변경이 없거나 기존 조건 구성을 유지하는 결과라면 별도 실패 표시 없이 현재 조건 구성을 유지한 채 편집 상태로 복귀한다.
- `query_changes_generated` -> `execution_failure_feedback_visible`
    - apply 이후 실행 단계에서 오류가 확인되면 execution failure feedback 경로로 넘긴다.

## User-visible Feedback

- 사용자는 query 기반 변경이 현재 condition 목록에 반영된 결과를 바로 확인할 수 있어야 한다.
- 실제로 바뀌는 내용이 없는 결과는 과도한 오류 피드백 없이 현재 조건 구성이 유지되는 상황으로 이해되어야 한다.

## Edge Cases / Failure Handling

- 구조화된 변경 결과에 실제로 바뀌는 조건이 없는 경우
- 기존 조건 구성을 유지하는 편이 더 적절해 현재 구성이 그대로 남는 경우
- apply 직후 실행 failure가 발생하는 경우
- 더 오래된 제출 결과가 늦게 도착하는 경우

## Acceptance Criteria

- [ ] Generate Filter Changes from Query가 적용 가능한 결과를 반환한 상황에서, 시스템이 해당 결과를 반영하면 현재 필터 조건 구성이 그 결과에 맞게 갱신되어야 한다.
- [ ] 적용 결과가 유효한 미저장 변경이면, 시스템은 사용자가 이어서 저장할 수 있는 상태를 유지해야 한다.
- [ ] 실질 변경이 없거나 기존 조건 구성을 유지하는 결과인 경우, 시스템은 실패 피드백을 만들지 않고 현재 조건 구성을 유지한 채 편집 상태로 복귀해야 한다.
- [ ] apply 이후 실행 계층 오류가 확인되면, 시스템은 conversion failure가 아니라 execution failure 경로로 분기해야 한다.
- [ ] 더 오래된 제출에서 나온 반영 결과는 현재 가장 최근 제출 상태를 덮어쓰지 않아야 한다.

## Permissions / Dependencies

- 구조화된 변경 결과와 현재 필터 조건 구성의 차이를 비교할 수 있어야 한다.
- 반영 이후에도 수동 조건 편집과 저장 흐름이 같은 현재 조건 구성을 기준으로 이어져야 한다.

## Observability / Analytics

- 변경 반영 완료 / 실질 변경 없음 / 기존 조건 구성 유지 / 반영 후 실행 실패 결과를 구분해 기록할 수 있어야 한다.
- apply 이후 save-ready 여부를 추적할 수 있어야 한다.

## Related Interactions

- [RCL-004-submit_collection_filter_query](RCL-004-submit_collection_filter_query.md)
- [RCL-004-generate_filter_changes_from_query](RCL-004-generate_filter_changes_from_query.md)
- [RCL-004-show_query_execution_failure_feedback](RCL-004-show_query_execution_failure_feedback.md)
- [RCL-005-change_collection_condition_value](../RCL-005-edit_collection_conditions/RCL-005-change_collection_condition_value.md)
- [RCL-002-save_collection_filter_changes](../RCL-002-manage_retrieval_collections/RCL-002-save_collection_filter_changes.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:109`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md)
