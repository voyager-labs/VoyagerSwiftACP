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

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 현재 페이지가 콜렉션 페이지인 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 입력된 이름이 비어 있는 경우
- OS 파일시스템 상 허용되지 않는 문자를 포함하는 경우
- 현재 콜렉션이 저장된 경로에 변경하려는 이름과 동일 이름 콜렉션이 이미 존재하는 경우

## Acceptance Criteria

- [ ] 현재 페이지가 콜렉션 페이지인 상태일 때, 사용자가 해당 인터랙션을 호출하면, 현재 콜렉션 파일
      이름을 수정할 수 있는 편집창이 나타남
- [ ] 사용자가 이름 변경을 시도했을 때, 변경이 성공했다면, 현재 콜렉션의 이름을 보여주는 곳이 새
      이름으로 모두 반영됨
- [ ] 사용자가 이름 변경을 시도했을 때, 입력된 이름이 비어 있거나 파일 시스템 상 유효하지 않은
      상태라면, 이름 변경을 수행하지 않고 오류 피드백을 표시함
- [ ] 사용자가 이름 변경을 시도했을 때, 현재 콜렉션이 저장된 경로에 동일 이름의 콜렉션 파일이 이미
      존재한다면, 이름 변경을 수행하지 않고 충돌 피드백을 표시함

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

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
