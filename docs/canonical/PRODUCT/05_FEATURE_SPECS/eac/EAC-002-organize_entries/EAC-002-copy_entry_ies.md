---
interaction_id: "EAC-002-copy_entry_ies"
interaction_type: "command"
feature: "Organize Entries"
category_key: "EAC"
feature_id: "EAC-002"
status: "배포 완료"
summary: "선택한 Entry를 클립보드에 복사"
related_region: "file_manager_window.content_pane.page_container.page_mode_directory"
menu: "Edit"
shortcut: "⌘C"
---

# Copy Entry(ies)

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 선택된 Entry 중 일부가 접근 불가 또는 존재하지 않는 경우
- <<AI>> 선택된 Entry 수가 매우 많아 클립보드 기록이 지연되는 경우

## Acceptance Criteria

- [ ] <<AI>> 하나 이상의 Entry가 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 선택한 Entry
      참조를 클립보드에 “복사” 의도로 저장함.
- [ ] <<AI>> 일부 Entry가 참조 불가한 상태일 때, 사용자가 해당 인터랙션을 호출하면, 참조 가능한
      Entry만 저장하고 제외된 대상과 사유를 사용자에게 안내함.
- [ ] <<AI>> Entry가 선택되지 않은 상태일 때, 사용자가 해당 인터랙션을 호출하면, 클립보드 상태를
      변경하지 않도록 함.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `44`
