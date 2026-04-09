---
interaction_id: "EAC-003-redo_entry_action"
interaction_type: "command"
feature: "Manage Entry Lifecycle"
category_key: "EAC"
feature_id: "EAC-003"
status: "배포 완료"
summary: "Undo로 되돌린 최근 Entry 관련 액션을 다시 적용"
related_region: "file_manager_window.content_pane.page_container.page_mode_directory"
menu: "Edit"
shortcut: "⇧⌘Z"
---

# Redo Entry Action

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> 다시 적용 가능한 최근 Entry 액션이 존재하는 상태
- <<AI>> Entry 관련 작업 실행이 진행 중이지 않은 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 외부 변경으로 재적용 전제가 깨진 경우
- <<AI>> Redo 대상 액션이 더 이상 유효하지 않은 경우

## Acceptance Criteria

- [ ] <<AI>> Redo 가능한 액션이 존재하는 상태일 때, 사용자가 해당 인터랙션을 호출하면, 가장 최근의
      Redo 가능한 Entry 액션을 다시 적용함.
- [ ] <<AI>> Redo가 성공한 상태일 때, 시스템이 처리하면, Undo 스택을 갱신하고 관련 UI를 갱신함.
- [ ] <<AI>> Redo가 불가능한 상태일 때, 사용자가 해당 인터랙션을 호출하면, 아무 변화도 발생하지
      않도록 함.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `57`
