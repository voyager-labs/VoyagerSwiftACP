---
interaction_id: "RCL-002-save_collection_filter_changes"
interaction_type: "command"
feature: "Manage Retrieval Collections"
category_key: "RCL"
feature_id: "RCL-002"
status: "배포 완료"
summary: "현재 콜렉션 파일에 필터 변경 사항을 저장해 정의를 갱신"
related_region: "file_manager_window.content_pane.content_header.page_menu_area"
menu: "file_menu"
shortcut: "⌘⌥S"
---

# Save Collection Filter Changes

## Intent

- 현재 콜렉션 파일에 필터 변경 사항을 저장해 정의를 갱신.
- `RCL-002`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- 사용자가 현재 filter를 새 collection으로 저장하거나 기존 collection 변경분을 저장/폐기할 때 호출된다.
- 저장된 `.voycoll` 파일을 열거나 이름 변경, 삭제, 닫기 전 경고가 필요한 때 호출된다.

## Preconditions

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 collection context 또는 저장된 `.voycoll` 파일 경로를 확인할 수 있어야 한다.

## Expected Outcome

- 현재 collection file에 query, scopes, conditions, 표시 상태를 함께 저장해 filter definition을 갱신한다.
- `save_ready` 상태의 유효한 filter definition만 저장 가능하다.
- `condition_value_incomplete` 상태에서 저장을 시도하면 `save_blocked`로 처리하고 불완전 condition을 저장하지 않는다.
- 저장 실패 시 `save_failed`를 표시하고 dirty change와 현재 collection page를 보존한다.

## State Changes

- `save_ready`와 `condition_value_incomplete`를 읽고 `editable`, `save_blocked`, `save_failed`를 쓴다.
- 저장 성공 시 dirty 기준점을 갱신하고 Composer를 `editable` 상태로 되돌린다.
- 저장 실패 시 dirty change, openedCollectionURL, collectionContext를 유지한다.

## User-visible Feedback

- 저장 가능 여부, 미저장 변경 표시, 저장 차단 사유, 저장 실패 recovery action을 사용자에게 노출한다.
- `save_blocked`는 미완성 condition을 수정하라는 안내로 표시한다.
- `save_failed`는 현재 collection page를 임의로 닫지 않고 재시도 가능하게 표시한다.

## Edge Cases / Failure Handling

- query, scopes, conditions가 모두 비어 있으면 collection 저장을 막는다.
- `condition_value_incomplete` 상태에서는 빈 condition 또는 절반짜리 Date range를 저장하지 않는다.
- storage 오류나 conflict가 발생하면 `save_failed`로 처리하고 dirty change를 보존한다.
- 검색 또는 filter apply가 진행 중이면 저장을 지연하거나 막아 불완전 payload를 저장하지 않는다.

## Acceptance Criteria

- [ ] `save_ready` 상태에서 Save를 실행하면 현재 `.voycoll` collection 파일이 갱신되어야 한다.
- [ ] `condition_value_incomplete` 상태에서 Save를 실행하면 `save_blocked`로 저장이 막혀야 한다.
- [ ] 저장 실패가 발생하면 `save_failed` 피드백과 dirty change가 유지되어야 한다.

## Permissions / Dependencies

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 collection context 또는 저장된 `.voycoll` 파일 경로를 확인할 수 있어야 한다.
- 관련 UI region: `file_manager_window.content_pane.content_header.page_menu_area`

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
- [RCL-002-save_current_filter_as_new_collection](RCL-002-save_current_filter_as_new_collection.md)
- [RCL-002-show_restored_collection_snapshot](RCL-002-show_restored_collection_snapshot.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:143`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Implementation references: `../voyager-app/docs/features/composer.md`, `../voyager-app/docs/features/entries-collections.md`, `../voyager-app/apps/macos/Voyager/Voyager/04_Features/Composer/Reducer/ComposerFeature.swift`, `../voyager-app/apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md), [collection_management_flow.md](../flows/collection_management_flow.md)
