---
interaction_id: "RCL-002-show_restored_collection_snapshot"
interaction_type: "display"
feature: "Manage Retrieval Collections"
category_key: "RCL"
feature_id: "RCL-002"
status: "기획 완료"
summary: "저장된 콜렉션을 다시 열 때 복원된 snapshot 결과를 먼저 표시해 이후 필요한 경우에만 refresh가 이어질 수 있게 함"
related_region: "file_manager_window.content_pane.page_container.page_mode_collection"
menu: "-"
shortcut: "-"
---

# Show Restored Collection Snapshot

## Intent

- 저장된 콜렉션을 다시 열 때 복원된 snapshot 결과를 먼저 표시해 이후 필요한 경우에만 refresh가 이어질 수 있게 함.
- `RCL-002`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- 사용자가 현재 filter를 새 collection으로 저장하거나 기존 collection 변경분을 저장/폐기할 때 호출된다.
- 저장된 `.voycoll` 파일을 열거나 이름 변경, 삭제, 닫기 전 경고가 필요한 때 호출된다.

## Preconditions

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 collection context 또는 저장된 `.voycoll` 파일 경로를 확인할 수 있어야 한다.

## Expected Outcome

- `snapshot_restored` 상태의 마지막 결과 snapshot과 definition metadata를 collection page에 표시한다.
- snapshot 표시 뒤에도 사용자는 Composer를 `editable` 상태로 열어 filter를 수정할 수 있어야 한다.
- snapshot이 없으면 `snapshot_fallback_required` 경로에서 definition-first refresh 안내를 보여준다.

## State Changes

- `snapshot_restored` 또는 `snapshot_fallback_required` 표시 상태를 읽어 page rendering state를 갱신한다.
- snapshot 표시가 성공해도 saved definition과 current filter context를 분리하지 않는다.
- 이후 사용자가 filter를 수정하면 `save_ready` 또는 `condition_value_incomplete`로 이어질 수 있다.

## User-visible Feedback

- 복원된 snapshot은 마지막 결과 기준임을 사용자가 이해할 수 있게 표시한다.
- fallback 필요 시 결과가 비어 있는 실패가 아니라 refresh 필요 상태로 안내한다.

## Edge Cases / Failure Handling

- snapshot 결과가 오래됐더라도 즉시 삭제하지 않고 RCL-003 stale/refresh 흐름으로 넘긴다.
- snapshot 표시 실패를 저장 실패와 혼동하지 않는다.
- definition-first fallback 시 저장된 조건 구성을 먼저 보여준다.

## Acceptance Criteria

- [ ] `snapshot_restored` 상태에서는 마지막 snapshot 결과가 즉시 표시되어야 한다.
- [ ] fallback 필요 시 저장된 definition이 먼저 복원되어야 한다.
- [ ] snapshot 표시 후 사용자는 filter를 계속 편집할 수 있어야 한다.

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
- [RCL-002-restore_saved_collection_snapshot](RCL-002-restore_saved_collection_snapshot.md)
- [RCL-002-save_collection_filter_changes](RCL-002-save_collection_filter_changes.md)
- [RCL-002-save_current_filter_as_new_collection](RCL-002-save_current_filter_as_new_collection.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:139`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Implementation references: `../voyager-app/docs/features/composer.md`, `../voyager-app/docs/features/entries-collections.md`, `../voyager-app/apps/macos/Voyager/Voyager/04_Features/Composer/Reducer/ComposerFeature.swift`, `../voyager-app/apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md), [collection_management_flow.md](../flows/collection_management_flow.md)
