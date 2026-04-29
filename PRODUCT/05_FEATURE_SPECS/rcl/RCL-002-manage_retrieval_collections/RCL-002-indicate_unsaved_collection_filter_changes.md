---
interaction_id: "RCL-002-indicate_unsaved_collection_filter_changes"
interaction_type: "display"
feature: "Manage Retrieval Collections"
category_key: "RCL"
feature_id: "RCL-002"
status: "배포 완료"
summary: "저장되지 않은 필터 변경 상태를 알리는 표시를 타이틀 바에 나타냄"
related_region: "file_manager_window.content_pane.content_header.page_info_area"
menu: "-"
shortcut: "-"
---

# Indicate Unsaved Collection Filter Changes

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 마지막 저장 상태 기준점이 존재하는 상태
- 현재 필터 구성이 기준점과 다른 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- TBD

## Acceptance Criteria

- [ ] 저장된 콜렉션 파일을 불러와 보고 있을 때, 현재 필터 구성이 마지막 저장 기준점과 다른 상태라면,
      타이틀 바에 미저장 인디케이터가 표시됨

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- [RCL-002-alert_unsasved_collection_filter_changes](RCL-002-alert_unsasved_collection_filter_changes.md)
- [RCL-002-delete_collection](RCL-002-delete_collection.md)
- [RCL-002-discard_collection_filter_changes](RCL-002-discard_collection_filter_changes.md)
- [RCL-002-import_smart_folder_as_collection](RCL-002-import_smart_folder_as_collection.md)
- [RCL-002-open_saved_collection](RCL-002-open_saved_collection.md)
- [RCL-002-rename_collection](RCL-002-rename_collection.md)
- [RCL-002-restore_saved_collection_snapshot](RCL-002-restore_saved_collection_snapshot.md)
- [RCL-002-save_collection_filter_changes](RCL-002-save_collection_filter_changes.md)
- [RCL-002-save_current_filter_as_new_collection](RCL-002-save_current_filter_as_new_collection.md)
- [RCL-002-show_restored_collection_snapshot](RCL-002-show_restored_collection_snapshot.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:141`
