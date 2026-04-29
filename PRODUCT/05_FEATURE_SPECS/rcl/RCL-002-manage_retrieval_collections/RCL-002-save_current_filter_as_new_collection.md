---
interaction_id: "RCL-002-save_current_filter_as_new_collection"
interaction_type: "command"
feature: "Manage Retrieval Collections"
category_key: "RCL"
feature_id: "RCL-002"
status: "배포 완료"
summary: "현재 필터 정의를 가진 새 콜렉션 파일을 생성해 로컬 스토리지에 저장"
related_region: "file_manager_window.content_pane.content_header.page_menu_area"
menu: "file_menu"
shortcut: "⌘⇧S"
---

# Save Current Filter As New Collection

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 현재 필터 구성이 존재하는 상태
- 미완성 컨디션이 존재하지 않는 상태
- 새 콜렉션을 생성할 수 있는 저장 경로/권한이 확보된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 콜렉션 이름이 비어 있거나 유효하지 않은 경우
- 저장 경로에 동일 이름의 콜렉션 파일이 이미 존재하는 경우

## Acceptance Criteria

- [ ] 현재 필터 구성이 존재하고 미완성 컨디션이 없는 상태일 때, 사용자가 해당 인터랙션을 호출하면,
      현재 필터 정의로 새 콜렉션 파일을 생성해 지정된 저장 경로에 저장함
- [ ] 콜렉션 이름이 비어 있거나 유효하지 않은 상태일 때, 사용자가 저장을 시도하면, 파일을 생성하지
      않고 이름 오류 피드백을 표시함
- [ ] 저장 경로에 동일 이름의 콜렉션 파일이 이미 존재하는 상태일 때, 사용자가 저장을 시도하면,
      파일을 생성하지 않고 이름 충돌 피드백을 표시함

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
- [RCL-002-rename_collection](RCL-002-rename_collection.md)
- [RCL-002-restore_saved_collection_snapshot](RCL-002-restore_saved_collection_snapshot.md)
- [RCL-002-save_collection_filter_changes](RCL-002-save_collection_filter_changes.md)
- [RCL-002-show_restored_collection_snapshot](RCL-002-show_restored_collection_snapshot.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:140`
