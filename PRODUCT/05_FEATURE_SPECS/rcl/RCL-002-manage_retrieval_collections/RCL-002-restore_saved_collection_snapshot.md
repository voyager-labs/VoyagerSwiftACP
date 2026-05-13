---
interaction_id: "RCL-002-restore_saved_collection_snapshot"
interaction_type: "background"
feature: "Manage Retrieval Collections"
category_key: "RCL"
feature_id: "RCL-002"
status: "기획 완료"
summary: "저장된 콜렉션을 다시 열 때 마지막 결과 snapshot과 정의 메타데이터를 먼저 복원해 즉시 확인 가능한 초기 상태를 구성"
related_region: "file_manager_window.content_pane.page_container.page_mode_collection"
menu: "-"
shortcut: "-"
---

# Restore Saved Collection Snapshot

## Intent

- 저장된 콜렉션을 다시 열 때 마지막 결과 snapshot과 정의 메타데이터를 먼저 복원해 즉시 확인 가능한 초기 상태를 구성.
- `RCL-002`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- 사용자가 현재 filter를 새 collection으로 저장하거나 기존 collection 변경분을 저장/폐기할 때 호출된다.
- 저장된 `.voycoll` 파일을 열거나 이름 변경, 삭제, 닫기 전 경고가 필요한 때 호출된다.

## Preconditions

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 collection context 또는 저장된 `.voycoll` 파일 경로를 확인할 수 있어야 한다.

## Expected Outcome

- `snapshot_restore_pending` 상태에서 `usable_snapshot` 여부를 판단한다.
- 사용 가능한 snapshot이면 `snapshot_restored` 상태로 마지막 결과 snapshot과 정의 메타데이터를 먼저 표시한다.
- 사용 가능한 snapshot이 없으면 `snapshot_fallback_required` 상태로 definition-first search fallback을 준비한다.
- fallback에서도 저장된 query/scopes/conditions definition은 보존해야 한다.

## State Changes

- `snapshot_restore_pending`을 읽고 `snapshot_restored` 또는 `snapshot_fallback_required`를 쓴다.
- `snapshot_restored`는 reopen 직후 즉시 표시 가능한 결과와 meta가 확보된 상태다.
- `snapshot_fallback_required`는 refresh 전에 저장된 definition을 먼저 되살려야 하는 상태다.

## User-visible Feedback

- snapshot이 복원되면 마지막 결과를 즉시 확인 가능한 초기 상태로 표시한다.
- fallback이 필요하면 빈 화면 실패가 아니라 정의 복원 후 refresh가 필요하다는 상태로 표시한다.
- background interaction은 별도 화면을 만들기보다 연결된 display/command interaction이 읽을 상태를 갱신한다.

## Edge Cases / Failure Handling

- snapshot이 없거나 meta가 definition과 맞지 않으면 `snapshot_fallback_required`로 처리한다.
- fallback은 저장된 definition을 버리지 않고 RCL-003 refresh 경계로 이어진다.
- restore 판단 실패를 save failure나 query execution failure와 섞지 않는다.

## Acceptance Criteria

- [ ] usable snapshot이 있으면 `snapshot_restored` 상태로 마지막 결과가 먼저 표시되어야 한다.
- [ ] usable snapshot이 없으면 `snapshot_fallback_required` 상태로 definition-first fallback이 시작되어야 한다.
- [ ] fallback 상황에서도 저장된 query/scopes/conditions definition은 보존되어야 한다.

## Permissions / Dependencies

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 collection context 또는 저장된 `.voycoll` 파일 경로를 확인할 수 있어야 한다.
- 관련 UI region: `file_manager_window.content_pane.page_container.page_mode_collection`

## Observability / Analytics

- interaction 실행 여부
- 요청/적용 성공 여부
- 실패 reason과 recovery action
- 마지막으로 적용된 filter snapshot

## Related Interactions

- [RCL-002-alert_unsasved_collection_filter_changes](RCL-002-alert_unsasved_collection_filter_changes.md)
- [RCL-002-delete_collection](RCL-002-delete_collection.md)
- [RCL-002-discard_collection_filter_changes](RCL-002-discard_collection_filter_changes.md)
- [RCL-002-import_smart_folder_as_collection](RCL-002-import_smart_folder_as_collection.md)
- [RCL-002-indicate_unsaved_collection_filter_changes](RCL-002-indicate_unsaved_collection_filter_changes.md)
- [RCL-002-open_saved_collection](RCL-002-open_saved_collection.md)
- [RCL-002-rename_collection](RCL-002-rename_collection.md)
- [RCL-002-save_collection_filter_changes](RCL-002-save_collection_filter_changes.md)
- [RCL-002-save_current_filter_as_new_collection](RCL-002-save_current_filter_as_new_collection.md)
- [RCL-002-show_restored_collection_snapshot](RCL-002-show_restored_collection_snapshot.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:138`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Implementation references: `../voyager-app/docs/features/composer.md`, `../voyager-app/docs/features/entries-collections.md`, `../voyager-app/apps/macos/Voyager/Voyager/04_Features/Composer/Reducer/ComposerFeature.swift`, `../voyager-app/apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md), [collection_management_flow.md](../flows/collection_management_flow.md)
