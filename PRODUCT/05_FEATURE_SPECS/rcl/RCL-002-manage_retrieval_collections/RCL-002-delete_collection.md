---
interaction_id: "RCL-002-delete_collection"
interaction_type: "command"
feature: "Manage Retrieval Collections"
category_key: "RCL"
feature_id: "RCL-002"
status: "배포 완료"
summary: "현재 보고 있는 콜렉션 파일을 삭제하고 닫음"
related_region: "file_manager_window.content_pane.content_header.page_menu_area"
menu: "file_menu"
shortcut: "-"
---

# Delete Collection

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

- 다른 탭/뷰에서 동일 콜렉션 페이지가 열려 있는 경우

## Acceptance Criteria

- [ ] 현재 페이지가 콜렉션 페이지인 상태일 때, 사용자가 해당 인터랙션을 호출하면, 삭제를 확인하는
      확인창이 나타남
- [ ] 사용자가 삭제를 시도했을 때, 삭제가 성공했다면, 현재 콜렉션 파일을 휴지통으로 옮기거나 완전히
      삭제하고, 현재 페이지를 닫음
- [ ] 사용자가 삭제를 확정했을 때, 다른 뷰에서 동일 콜렉션 페이지가 열려 있는 상태라면, 해당 뷰가
      대상 없음 상태로 전환됨

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- [RCL-002-alert_unsasved_collection_filter_changes](RCL-002-alert_unsasved_collection_filter_changes.md)
- [RCL-002-discard_collection_filter_changes](RCL-002-discard_collection_filter_changes.md)
- [RCL-002-import_smart_folder_as_collection](RCL-002-import_smart_folder_as_collection.md)
- [RCL-002-indicate_unsaved_collection_filter_changes](RCL-002-indicate_unsaved_collection_filter_changes.md)
- [RCL-002-open_saved_collection](RCL-002-open_saved_collection.md)
- [RCL-002-rename_collection](RCL-002-rename_collection.md)
- [RCL-002-restore_saved_collection_snapshot](RCL-002-restore_saved_collection_snapshot.md)
- [RCL-002-save_collection_filter_changes](RCL-002-save_collection_filter_changes.md)
- [RCL-002-save_current_filter_as_new_collection](RCL-002-save_current_filter_as_new_collection.md)
- [RCL-002-show_restored_collection_snapshot](RCL-002-show_restored_collection_snapshot.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:145`
