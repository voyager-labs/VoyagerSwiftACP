---
interaction_id: "RCL-002-restore_saved_collection_snapshot"
interaction_type: "background"
feature: "Manage Retrieval Collections"
category_key: "RCL"
feature_id: "RCL-002"
status: "기획 완료"
summary: "저장된 콜렉션을 다시 열 때 조건 구성과 저장된 결과 정보·관련 메타데이터를 함께 읽고, 바로 복원 가능한 결과인지 판단해 초기 복원 경로를 결정"
related_region: "file_manager_window.content_pane.page_container.page_mode_collection"
menu: "-"
shortcut: "-"
---

# Restore Saved Collection Snapshot

## Intent

- 저장된 collection을 다시 열 때 조건 구성과 저장된 결과 정보·관련 메타데이터를 함께 읽어, 즉시 복원 가능한 저장 결과가 있으면 곧바로 결과 맥락을 복원하고 그렇지 않으면 조건 구성 기준의 재검색 경로로 자연스럽게 넘어가게 한다.

## Trigger / Entry Points

- [RCL-002-open_saved_collection](RCL-002-open_saved_collection.md) 이후 reopen 경로가 시작되었을 때

## Preconditions

- 저장된 collection을 여는 흐름이 시작된 상태
- 저장된 collection 조건 구성을 읽을 수 있고 저장된 결과 정보·관련 메타데이터가 즉시 복원에 쓸 수 있는지 판단할 수 있는 상태

## Expected Outcome

- 즉시 복원 가능한 저장 결과가 있으면 결과를 바로 복원하고, 그렇지 않으면 열기 자체를 실패로 끝내지 않고 조건 구성 기준의 재검색 경로로 전환한다.

## State Changes

- `snapshot_restore_pending` -> `snapshot_restored`
    - 저장된 결과와 관련 메타데이터, 조건 일치 여부가 모두 맞으면 즉시 복원 가능한 상태로 전환한다.
- `snapshot_restore_pending` -> `snapshot_fallback_required`
    - 즉시 복원 가능한 저장 결과가 아니면 조건 구성 기준의 재검색이 필요한 상태로 전환한다.

## User-visible Feedback

- 사용자는 다시 열기 직후 즉시 복원 가능한 저장 결과가 있을 때 결과를 먼저 볼 수 있어야 한다.
- 저장된 결과가 즉시 복원에 쓰기 어렵더라도 열기 전체가 실패했다고 느끼지 않도록 대체 경로 전환이 자연스러워야 한다.

## Edge Cases / Failure Handling

- 저장된 결과는 있으나 관련 메타데이터가 없어 즉시 복원에 쓰기 어려운 경우
- 저장된 결과와 조건 구성이 서로 맞지 않아 즉시 복원을 건너뛰어야 하는 경우
- 조건 구성은 유효하지만 저장된 결과를 즉시 복원에 쓰기 어려워 재검색 경로로 전환되는 경우
- 최신성 판단에 필요한 메타데이터가 없어 최신 여부 판단 이전에 즉시 복원 대상에서 제외해야 하는 경우

## Acceptance Criteria

- [ ] 저장된 collection을 다시 열 때, 시스템은 조건 구성과 저장된 결과 정보·관련 메타데이터를 함께 읽어 복원 경로를 판단해야 한다.
- [ ] 시스템은 저장된 결과, 관련 메타데이터, 조건 일치 여부를 모두 만족할 때만 해당 결과를 즉시 복원 가능하다고 판단해야 한다.
- [ ] 즉시 복원 가능한 저장 결과가 있으면, 시스템은 결과를 먼저 표시할 수 있는 `snapshot_restored` 경로를 사용해야 한다.
- [ ] 저장된 결과가 즉시 복원 가능하지 않다면, 시스템은 열기를 실패로 끝내지 않고 `snapshot_fallback_required` 경로로 전환해 조건 구성 기준의 재검색 경로를 이어가야 한다.
- [ ] 최신성 메타데이터가 부족하면, 시스템은 저장된 결과를 그대로 신뢰하지 않고 즉시 복원 가능하지 않은 것으로 처리해야 한다.

## Permissions / Dependencies

- collection 조건 구성, 저장된 결과 정보, 관련 메타데이터, 조건 일치 비교 정보가 모두 접근 가능해야 한다.
- 다시 열기 대체 경로는 saved collection open의 기존 alert/조건 구성 경계와 충돌하지 않아야 한다.

## Observability / Analytics

- 즉시 복원 완료 / 재검색 전환 필요를 분리해 기록할 수 있어야 한다.
- 즉시 복원이 어려운 이유가 메타데이터 부족인지 조건 불일치인지 구분 가능해야 한다.

## Related Interactions

- [RCL-002-open_saved_collection](RCL-002-open_saved_collection.md)
- [RCL-002-show_restored_collection_snapshot](RCL-002-show_restored_collection_snapshot.md)
- [RCL-002-save_collection_filter_changes](RCL-002-save_collection_filter_changes.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:130`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md)
