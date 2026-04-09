---
interaction_id: "EAC-003-empty_trash"
interaction_type: "command"
feature: "Manage Entry Lifecycle"
category_key: "EAC"
feature_id: "EAC-003"
status: "배포 완료"
summary: "휴지통에 있는 모든 Entry를 영구 삭제"
related_region: "file_manager_window.content_pane.page_container.page_mode_directory"
menu: "File"
shortcut: "⇧⌘⌫"
---

# Empty Trash

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> 휴지통에 하나 이상의 Entry가 존재하는 상태
- <<AI>> 휴지통 비우기에 대한 사용자 확인을 획득한 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 사용자가 확인 다이얼로그에서 취소하는 경우
- <<AI>> 일부 항목이 잠김/권한 문제로 삭제 불가능한 경우
- <<AI>> 항목 수가 많아 삭제 시간이 길어 진행 표시가 필요한 경우

## Acceptance Criteria

- [ ] <<AI>> 사용자 확인이 완료된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 휴지통의 모든
      Entry를 영구 삭제함.
- [ ] <<AI>> 사용자가 취소한 상태일 때, 시스템이 처리를 종료하면, 휴지통 비우기를 수행하지 않도록
      함.
- [ ] <<AI>> 일부 항목 삭제가 실패하는 상태일 때, 시스템이 비우기를 수행하면, 성공/실패 항목과
      사유를 사용자에게 안내함.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `55`
