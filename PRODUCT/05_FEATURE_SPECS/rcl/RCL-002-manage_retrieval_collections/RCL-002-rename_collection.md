---
interaction_id: "RCL-002-rename_collection"
interaction_type: "input"
feature: "Manage Retrieval Collections"
category_key: "RCL"
feature_id: "RCL-002"
status: "배포 완료"
summary: "현재 보고 있는 콜렉션의 파일 이름을 변경"
related_region: "file_manager_window.content_pane.content_header.page_menu_area"
menu: "-"
shortcut: "-"
---

# Rename Collection

## Intent

- 현재 보고 있는 콜렉션의 파일 이름을 변경.
- `RCL-002`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- 사용자가 현재 filter를 새 collection으로 저장하거나 기존 collection 변경분을 저장/폐기할 때 호출된다.
- 저장된 `.voycoll` 파일을 열거나 이름 변경, 삭제, 닫기 전 경고가 필요한 때 호출된다.

## Preconditions

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 collection context 또는 저장된 `.voycoll` 파일 경로를 확인할 수 있어야 한다.

## Expected Outcome

- 현재 보고 있는 콜렉션의 파일 이름을 변경.
- collection file은 query, scopes, conditions와 표시 상태를 함께 보존해야 한다.
- 저장 중이거나 검색/필터 요청이 진행 중이면 불완전한 상태 저장을 막아야 한다.
- 미저장 변경이 있을 때는 title affordance 또는 경고 흐름으로 이탈 위험을 표시해야 한다.

## State Changes

- openedCollectionURL, collectionContext, lastFiltersResponse, unsaved-change 상태를 갱신한다.
- Save As는 새 `.voycoll` 패키지 파일을 만들고 현재 context를 저장 기준으로 삼는다.
- discard는 마지막 저장본 또는 복원된 snapshot 기준으로 draft를 되돌린다.

## User-visible Feedback

- 저장 가능 여부, 미저장 변경 표시, 파일 이름 변경 결과, 삭제/닫기 경고를 사용자에게 노출한다.
- 저장 실패나 삭제 실패는 현재 collection page를 임의로 닫지 않고 recovery action을 유지한다.

## Edge Cases / Failure Handling

- query, scopes, conditions가 모두 비어 있으면 collection 저장을 막는다.
- 검색 또는 filter apply가 진행 중이면 저장을 지연하거나 막아 불완전 payload를 저장하지 않는다.
- 레거시 단일 파일 `.voycoll`은 열 수 있되 저장 시 현재 패키지 포맷으로 정규화될 수 있다.
- 입력이 유효하지 않으면 저장/적용을 실행하지 않고 수정 가능한 오류 상태를 유지한다.

## Acceptance Criteria

- [ ] 현재 filter가 비어 있지 않은 상황에서 Save As를 실행하면 `.voycoll` collection 파일이 생성되어야 한다.
- [ ] 저장된 collection을 수정하면 미저장 변경 표시가 나타나야 한다.
- [ ] 미저장 변경이 있는 상태에서 이탈하면 경고 또는 discard/save 선택지가 제공되어야 한다.

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
- [RCL-002-restore_saved_collection_snapshot](RCL-002-restore_saved_collection_snapshot.md)
- [RCL-002-save_collection_filter_changes](RCL-002-save_collection_filter_changes.md)
- [RCL-002-save_current_filter_as_new_collection](RCL-002-save_current_filter_as_new_collection.md)
- [RCL-002-show_restored_collection_snapshot](RCL-002-show_restored_collection_snapshot.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:144`
- Implementation references: `../voyager-app/docs/features/composer.md`, `../voyager-app/docs/features/entries-collections.md`, `../voyager-app/apps/macos/Voyager/Voyager/04_Features/Composer/Reducer/ComposerFeature.swift`, `../voyager-app/apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`
- Flows: [collection_management_flow.md](../flows/collection_management_flow.md)
