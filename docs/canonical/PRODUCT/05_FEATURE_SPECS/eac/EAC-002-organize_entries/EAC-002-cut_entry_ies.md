---
interaction_id: "EAC-002-cut_entry_ies"
interaction_type: "command"
feature: "Organize Entries"
category_key: "EAC"
feature_id: "EAC-002"
status: "배포 완료"
summary: "선택한 Entry를 이동을 위한 잘라내기 상태로 클립보드에 저장"
related_region: "file_manager_window.content_pane.page_container.page_mode_directory"
menu: "Edit"
shortcut: "⌘X"
---

# Cut Entry(ies)

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

- <<AI>> 선택된 Entry가 이동 불가(권한/시스템 보호/읽기 전용 볼륨)일 가능성이 있는 경우
- <<AI>> 기존 클립보드에 다른 복사/잘라내기 대상이 저장되어 있는 경우

## Acceptance Criteria

- [ ] <<AI>> 하나 이상의 Entry가 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 선택한 Entry
      참조를 클립보드에 “이동(잘라내기)” 의도로 저장함.
- [ ] <<AI>> 기존 클립보드에 대상이 존재하는 상태일 때, 사용자가 해당 인터랙션을 호출하면, 이전
      클립보드 대상을 새 대상으로 대체함.
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
- Source line: `45`
