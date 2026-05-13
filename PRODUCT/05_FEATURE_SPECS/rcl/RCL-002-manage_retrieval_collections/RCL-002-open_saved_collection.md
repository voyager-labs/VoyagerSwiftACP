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

- 저장된 콜렉션을 선택해 해당 콜렉션 페이지를 열고 복원 흐름을 시작.
- `RCL-002`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- 사용자가 현재 filter를 새 collection으로 저장하거나 기존 collection 변경분을 저장/폐기할 때 호출된다.
- 저장된 `.voycoll` 파일을 열거나 이름 변경, 삭제, 닫기 전 경고가 필요한 때 호출된다.

## Preconditions

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 collection context 또는 저장된 `.voycoll` 파일 경로를 확인할 수 있어야 한다.

## Expected Outcome

- 저장된 `.voycoll` collection을 열 때 definition과 persisted snapshot/meta를 읽어 `snapshot_restore_pending` 상태를 시작한다.
- `usable_snapshot`이 있으면 restore 흐름이 즉시 표시 가능한 snapshot으로 이어질 수 있어야 한다.
- snapshot이 없거나 사용할 수 없으면 definition-first fallback을 준비한다.
- collection open은 저장된 query/scopes/conditions/display state를 함께 복원해야 한다.

## State Changes

- `snapshot_restore_pending`을 쓴다.
- openedCollectionURL, collectionContext, persisted snapshot/meta를 reopen 기준으로 갱신한다.
- 이후 `RCL-002-restore_saved_collection_snapshot`이 `snapshot_restored` 또는 `snapshot_fallback_required`를 결정한다.

## User-visible Feedback

- collection page는 복원 판단 중임을 즉시 표시하고, 사용 가능한 snapshot이 있으면 빠르게 표시될 수 있어야 한다.
- snapshot fallback이 필요한 경우에도 파일 열기 자체를 실패처럼 표시하지 않는다.

## Edge Cases / Failure Handling

- `.voycoll` 파일이 legacy single-file 형식이면 읽기는 허용하되 저장 시 현재 package format으로 정규화될 수 있다.
- snapshot/meta가 손상되어도 저장된 definition을 우선 복원하는 fallback 경로를 남긴다.
- open 실패와 query execution failure를 같은 피드백으로 합치지 않는다.

## Acceptance Criteria

- [ ] 저장된 collection을 열면 `snapshot_restore_pending` 상태가 시작되어야 한다.
- [ ] usable snapshot이 없으면 definition-first fallback 경로가 준비되어야 한다.
- [ ] open 실패는 query execution failure feedback과 구분되어야 한다.

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

- [RCL-002-alert_unsaved_collection_filter_changes](RCL-002-alert_unsaved_collection_filter_changes.md)
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
- Implementation references: `../voyager-app/docs/features/composer.md`, `../voyager-app/docs/features/entries-collections.md`, `../voyager-app/apps/macos/Voyager/Voyager/04_Features/Composer/Reducer/ComposerFeature.swift`, `../voyager-app/apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md), [collection_management_flow.md](../flows/collection_management_flow.md)
