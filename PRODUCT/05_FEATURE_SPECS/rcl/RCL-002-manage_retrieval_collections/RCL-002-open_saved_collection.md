---
interaction_id: "RCL-002-open_saved_collection"
interaction_type: "command"
feature: "Manage Retrieval Collections"
category_key: "RCL"
feature_id: "RCL-002"
status: "기획 완료"
summary: "저장된 콜렉션을 선택해 해당 콜렉션 페이지를 열고 복원 흐름을 시작"
related_region: "file_manager_window.content_pane.page_container.page_mode_collection"
menu: "-"
shortcut: "-"
---

# Open Saved Collection

## Intent

- 저장된 collection을 다시 열 때 조건 구성과 저장된 결과 정보·관련 메타데이터를 함께 읽기 시작하고, 다시 열기 판단을 `snapshot_restore_pending` 상태에서 일관되게 시작하게 한다.

## Trigger / Entry Points

- 사용자가 저장된 collection 파일 또는 목록 항목을 열었을 때
- 현재 세션에서 해당 collection을 페이지 형태로 다시 복원해야 할 때

## Preconditions

- 저장된 collection 파일 또는 목록 항목이 존재하는 상태
- 사용자가 해당 collection을 다시 열 수 있는 경로와 권한이 확보된 상태

## Expected Outcome

- 시스템은 열기 직후 조건 구성과 저장된 결과 정보·관련 메타데이터를 함께 읽는 다시 열기 경로를 시작해야 한다.
- 즉시 복원 가능한 저장 결과인지 아직 확정되기 전까지는 `snapshot_restore_pending` 상태를 통해 이후 복원 또는 대체 분기를 준비해야 한다.

## State Changes

- `snapshot_restore_pending` 진입
    - 저장된 collection 열기 요청이 시작되면 다시 열기 흐름은 현재 편집 상태와 무관하게 조건 구성과 저장된 결과 정보·관련 메타데이터를 함께 읽는 판단 상태로 진입한다.

## User-visible Feedback

- 사용자는 저장된 collection을 열자마자 복원 또는 대체 경로 판단이 진행 중이라는 점만 자연스럽게 느끼면 되며, 저장 결과 정보가 없다는 이유만으로 즉시 실패했다고 느끼지 않아야 한다.

## Edge Cases / Failure Handling

- 저장 결과 정보는 있지만 즉시 복원에 쓰기 어려운 경우
- 일부 지원되지 않는 조건이 포함되어 있지만 나머지 조건으로는 열 수 있는 경우
- 파일 해석 자체가 실패하거나 조건 구성이 비어 있어 열기를 계속할 수 없는 경우
- 동일 collection이 다른 탭 또는 윈도우에 열려 있어도 현재 open 요청은 별도로 처리되는 경우

## Acceptance Criteria

- [ ] 사용자가 저장된 collection을 열면, 시스템은 해당 collection page를 열고 조건 구성과 저장된 결과 정보·관련 메타데이터를 함께 읽는 다시 열기 경로를 시작해야 한다.
- [ ] 다시 열기 경로가 시작되면, 시스템은 즉시 복원 가능한 저장 결과인지 곧바로 단정하지 않고 먼저 `snapshot_restore_pending` 상태를 거쳐 이후 복원 또는 대체 판단으로 이어가야 한다.
- [ ] 즉시 복원 가능한 저장 결과가 있으면, 시스템은 다시 열 때마다 곧바로 재검색하지 않고 저장된 결과 우선 복원 경로를 먼저 적용할 수 있어야 한다.
- [ ] 즉시 복원 가능한 저장 결과가 없다면, 시스템은 그 부재만으로 열기를 실패로 처리하지 않고 조건 구성 기준의 재검색 경로로 계속 진행할 수 있어야 한다.
- [ ] collection 파일 자체가 손상되었거나 조건 구성을 복원할 수 없으면, 시스템은 실패를 안내하고 page 상태를 일관되게 유지해야 한다.

## Permissions / Dependencies

- collection 조건 구성, 저장된 결과 정보, 관련 메타데이터에 접근할 수 있어야 한다.
- 즉시 복원 가능한 저장 결과인지에 대한 최종 판단과 복원/대체 분기는 [RCL-002-restore_saved_collection_snapshot](RCL-002-restore_saved_collection_snapshot.md)에서 이어진다.

## Observability / Analytics

- open 요청이 snapshot 판단 단계까지 진입했는지 기록할 수 있어야 한다.
- 조건 구성 복구 실패와 저장 결과 정보를 즉시 복원에 쓰기 어려운 경우를 구분 가능한 이벤트 구조가 필요하다.

## Related Interactions

- [RCL-002-alert_unsasved_collection_filter_changes](RCL-002-alert_unsasved_collection_filter_changes.md)
- [RCL-002-delete_collection](RCL-002-delete_collection.md)
- [RCL-002-discard_collection_filter_changes](RCL-002-discard_collection_filter_changes.md)
- [RCL-002-import_smart_folder_as_collection](RCL-002-import_smart_folder_as_collection.md)
- [RCL-002-indicate_unsaved_collection_filter_changes](RCL-002-indicate_unsaved_collection_filter_changes.md)
- [RCL-002-rename_collection](RCL-002-rename_collection.md)
- [RCL-002-restore_saved_collection_snapshot](RCL-002-restore_saved_collection_snapshot.md)
- [RCL-002-save_collection_filter_changes](RCL-002-save_collection_filter_changes.md)
- [RCL-002-save_current_filter_as_new_collection](RCL-002-save_current_filter_as_new_collection.md)
- [RCL-002-show_restored_collection_snapshot](RCL-002-show_restored_collection_snapshot.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:137`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md)
