---
interaction_id: "RCL-001-show_collection_scope_change_feedback"
interaction_type: "display"
feature: "Define Collection Scope"
category_key: "RCL"
feature_id: "RCL-001"
status: "기획 완료"
summary: "스코프 변경 직후 무엇이 바뀌었는지 알 수 있는 변경 피드백과 최소 되돌리기 상태를 보여줌"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Show Collection Scope Change Feedback

## Intent

- 사용자가 스코프를 바꾼 직후 무엇이 달라졌는지 바로 이해할 수 있게 한다.
- 필요하면 방금 한 변경을 최소 되돌리기로 복원할 수 있게 한다.
- 스코프 의미 변경과 결과 반영 상태를 같은 것으로 오해하지 않게 해, 변경은 적용되었지만 결과 표시가 아직 따라오지 않았거나 실패했는지를 분리해 이해할 수 있게 한다.

## Trigger / Entry Points

- 스코프를 추가, 제거, 제외, 복원한 직후
- 하위 폴더 포함 규칙을 바꿔 현재 범위 의미가 달라진 직후

## Preconditions

- Collection Filter Composer가 열린 상태
- 최근 스코프 변경이 존재하는 상태

## Expected Outcome

- 변경 피드백은 최근 1개의 스코프 변경만 대상으로 표시한다.
- 변경 피드백은 최소 아래 3가지를 함께 보여줘야 한다.
  - 무엇이 바뀌었는지
  - 현재 결과가 왜 달라졌는지
  - 되돌리기 가능한지
- 되돌리기가 가능한 상태에서는 같은 피드백 안에서 undo 진입이 가능해야 한다.
- 변경 피드백은 `정상 반영`, `반영 지연`, `반영 실패` 상태 중 하나로 읽혀야 한다.
- 이 문서는 최소 `change_feedback_visible`, `change_feedback_delayed`, `change_feedback_failed`, `redo_available` 상태를 구분해 다뤄야 한다.
- 이 피드백은 필요 시 `undo_available` 상태와 함께 읽히고, undo 이후에는 `redo_available` 상태와 이어질 수 있다.
- `change_feedback_delayed`는 최근 스코프 변경 자체가 무효라는 뜻이 아니라, 변경된 scope 의미는 이미 갱신되었지만 결과 영역 반영이 아직 최신 상태가 아니라는 뜻으로 읽혀야 한다.
- `change_feedback_failed`는 최근 스코프 변경을 성공처럼 표시할 수 없다는 뜻이지만, 실패 원인이 결과 반영 또는 상태 갱신에 있고 현재 scope definition 자체를 자동으로 이전 상태로 롤백했다는 뜻으로 읽히면 안 된다.
- 실패가 발생해도 사용자는 현재 scope meaning이 유지되는지, 별도 재시도 없이 현재 상태를 그대로 둘 수 있는지, 또는 후속 refresh/재계산이 필요한지만 이해할 수 있으면 된다.

## State Changes

- 최근 스코프 변경이 발생하면 변경 피드백이 노출된다.
- 연속 변경이 발생하면 이전 피드백은 누적하지 않고 가장 최근 변경 기준으로 교체된다.
- 최근 변경이 즉시 적용 불가 상태가 되거나, 더 이상 복원 가능한 이전 상태가 없으면 undo 진입은 사라지고 변경 피드백만 남는다.
- 결과 반영이 지연되는 동안에는 변경 피드백이 지연 상태로 전환되고, 결과 영역은 갱신 완료 전까지 최종 반영값처럼 읽히면 안 된다.
- 지연 상태가 끝나면 변경 피드백은 정상 반영 상태 또는 실패 상태 중 하나로 전환되어야 한다.
- redo가 가능한 경우에는 현재 피드백이 다시 적용 가능(`redo_available`) 상태와 함께 읽혀야 한다.
- 결과 반영이 늦으면 `change_feedback_delayed`, 실패하면 `change_feedback_failed`, 정상 반영이면 `change_feedback_visible` 상태로 읽혀야 한다.
- `change_feedback_visible`에서 `change_feedback_delayed`로 전환되더라도 현재 scope summary와 내부 scope definition은 최신 변경 기준을 유지할 수 있어야 하며, 지연은 결과 표현 seam에서만 해석되어야 한다.
- `change_feedback_failed`로 전환될 때 시스템은 성공 반영 상태를 제거해야 하지만, 사용자가 방금 수행한 scope edit의 의미 자체를 자동으로 되돌린 것처럼 보이게 하면 안 된다.
- undo를 수행하면 피드백 기준점은 직전 scope change 이전 상태로 돌아가고, 그 이후에는 `redo_available`을 통해 방금 취소한 변경 1건만 다시 적용 가능한 상태로 이어질 수 있다.

## User-visible Feedback

- 변경 피드백은 단순 강조 표시가 아니라 변경 유형을 식별 가능한 문장 또는 라벨로 보여줘야 한다.
- 변경 유형은 최소 add / remove / exclude / restore / include-subfolders change 중 하나로 읽혀야 한다.
- 결과 변화는 "현재 결과가 줄어듦 / 늘어남 / 범위가 바뀜" 수준으로라도 이해 가능해야 한다.
- undo가 가능한 상태에서는 피드백 안에 undo 진입 요소가 함께 보여야 한다.
- 결과 반영이 지연되는 동안에는 변경은 적용되었지만 결과는 아직 갱신 중이라는 상태가 분리되어 보여야 한다.
- 지연이 실패나 타임아웃으로 끝나면, 시스템은 성공 반영 상태 대신 실패 상태와 재시도 또는 현재 상태 유지 정보를 보여줘야 한다.
- 이때 시스템은 contract 용어 기준으로 `변경 반영 지연 상태`와 `변경 반영 실패 상태`를 구분해 보여줘야 한다.
- 실패 상태에서는 "변경이 적용되지 않음"과 "결과 갱신 확인에 실패함"을 혼동하게 만드는 표현을 피하고, 사용자는 현재 scope meaning은 유지된 채 결과 반영 확인이 끝나지 않았다는 점을 이해할 수 있어야 한다.
- 재시도 진입점을 제공하더라도 그것이 scope edit를 다시 수행하는 것인지, 변경된 scope를 기준으로 결과 반영을 다시 시도하는 것인지가 혼동되지 않아야 한다.

## Edge Cases / Failure Handling

- 연속으로 여러 변경이 발생하더라도 현재 피드백은 가장 최근 변경 1건만 기준으로 유지해야 한다.
- 되돌리기가 불가능한 상태에서는 undo 진입 요소를 숨기거나 비활성화해야 한다.
- 변경 적용이 실패한 경우에는 성공한 변경처럼 보이는 피드백을 보여주면 안 된다.
- 결과 반영이 지연되는 동안에는 변경은 적용되었지만 결과 반영이 아직 진행 중이라는 별도 지연 상태를 표시해야 하며, 완료 전 결과를 확정값처럼 보이면 안 된다.
- 결과 반영 실패 이후에도 현재 scope summary가 최신 변경 기준을 유지한다면, 시스템은 사용자가 "변경은 남아 있고 결과 확인만 실패했다"고 해석할 수 있게 해야 한다.
- 결과 반영 실패가 발생해도 별도 undo interaction이 명시적으로 호출되지 않았다면, 시스템은 자동 복구가 일어난 것처럼 현재 scope summary를 이전 의미로 되돌려 보여주면 안 된다.

## Acceptance Criteria

- [ ] 사용자가 스코프를 추가, 제거, 제외, 복원한 직후, 시스템은 최근 변경 1건에 대해 무엇이 바뀌었는지 식별 가능한 변경 피드백을 보여줘야 한다.
- [ ] 사용자가 방금 한 스코프 변경을 되돌리고 싶을 때, 시스템은 undo가 가능한 경우 같은 피드백 안에서 즉시 되돌리기 흐름으로 이어질 수 있게 해야 한다.
- [ ] 연속으로 변경이 발생하는 상황에서, 시스템은 이전 피드백을 누적하지 않고 가장 최근 변경 기준의 피드백으로 교체해야 한다.
- [ ] 변경 직후 필터가 다시 반영되는 상황에서, 시스템은 변경 피드백 안에서 결과 변화와의 관계를 이해할 수 있게 해야 한다.
- [ ] 변경 적용이 실패한 상황에서, 시스템은 성공한 변경처럼 보이는 피드백 대신 실패 사실을 구분해 보여줘야 한다.
- [ ] 결과 반영이 지연되는 상황에서, 시스템은 변경 피드백을 지연 상태로 표시하고 결과가 아직 최종 반영값이 아님을 구분해 보여줘야 한다.
- [ ] 결과 반영 지연이 실패 또는 타임아웃으로 끝나는 상황에서, 시스템은 성공 반영 상태 대신 실패 상태와 현재 상태 유지 또는 재시도 가능 여부를 보여줘야 한다.
- [ ] 결과 반영 실패가 발생했지만 별도 undo interaction은 호출되지 않은 상황에서, 시스템은 현재 scope meaning이 자동으로 이전 상태로 되돌아간 것처럼 보이지 않게 해야 한다.
- [ ] 재시도 진입점을 노출하는 상황에서, 시스템은 그것이 scope edit의 재실행이 아니라 변경된 scope 기준 결과 반영의 후속 시도임을 혼동 없이 이해할 수 있게 해야 한다.

## Permissions / Dependencies

- `RCL-001-undo_collection_filter_changes`
- Contract: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flow: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)

## Observability / Analytics

- 스코프 변경 피드백 표시
- 스코프 변경 피드백에서 되돌리기 진입
- 표시된 변경 유형
- 결과 반영 지연 상태 표시

## Related Interactions

- [RCL-001-add_directory_to_collection_scope](RCL-001-add_directory_to_collection_scope.md)
- [RCL-001-collapse_collection_filter_composer](RCL-001-collapse_collection_filter_composer.md)
- [RCL-001-exclude_directory_from_collection_scope](RCL-001-exclude_directory_from_collection_scope.md)
- [RCL-001-open_collection_filter_composer](RCL-001-open_collection_filter_composer.md)
- [RCL-001-open_collection_scope_menu](RCL-001-open_collection_scope_menu.md)
- [RCL-001-redo_collection_filter_changes](RCL-001-redo_collection_filter_changes.md)
- [RCL-001-remove_directory_from_collection_scope](RCL-001-remove_directory_from_collection_scope.md)
- [RCL-001-restore_directory_to_collection_scope](RCL-001-restore_directory_to_collection_scope.md)
- [RCL-001-search_collection_scope_candidates](RCL-001-search_collection_scope_candidates.md)
- [RCL-001-show_collection_scope_candidate_disambiguation](RCL-001-show_collection_scope_candidate_disambiguation.md)
- [RCL-001-show_collection_scope_exceptions](RCL-001-show_collection_scope_exceptions.md)
- [RCL-001-show_collection_scope_summary](RCL-001-show_collection_scope_summary.md)
- [RCL-001-toggle_collection_scope_subfolder_inclusion](RCL-001-toggle_collection_scope_subfolder_inclusion.md)
- [RCL-001-undo_collection_filter_changes](RCL-001-undo_collection_filter_changes.md)
## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:129`
- Contracts: [collection_scope_contract.toml](../contracts/collection_scope_contract.toml)
- Flows: [collection_scope_editing_flow.md](../flows/collection_scope_editing_flow.md)
