---
interaction_id: "EAC-003-delete_entry_ies_immediately"
interaction_type: "command"
feature: "Manage Entry Lifecycle"
category_key: "EAC"
feature_id: "EAC-003"
status: "배포 완료"
summary: "선택한 Entry를 휴지통을 거치지 않고 즉시 영구 삭제"
related_region: "file_manager_window.content_pane.page_container.page_mode_directory"
menu: "File"
shortcut: "⌥⌘⌫"
---

# Delete Entry(ies) Immediately

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태
- <<AI>> 영구 삭제에 대한 사용자 확인을 획득한 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 사용자가 확인 다이얼로그에서 취소하는 경우
- <<AI>> 권한 부족/파일 잠금으로 삭제가 실패하는 경우
- <<AI>> 일부만 삭제 가능해 부분 성공이 발생하는 경우

## Acceptance Criteria

- [ ] <<AI>> 사용자 확인이 완료된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 선택한 Entry를
      휴지통 없이 영구 삭제함.
- [ ] <<AI>> 사용자가 삭제를 취소한 상태일 때, 시스템이 처리를 종료하면, 삭제를 수행하지 않도록 함.
- [ ] <<AI>> 일부만 삭제 가능한 상태일 때, 시스템이 삭제를 수행하면, 성공/실패 항목과 사유를
      사용자에게 안내함.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `53`
