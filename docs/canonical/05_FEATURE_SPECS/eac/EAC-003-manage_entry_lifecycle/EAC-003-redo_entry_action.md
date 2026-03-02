# Redo Entry Action

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EAC-003-redo_entry_action |
| Interaction Type | command |
| Feature | Manage Entry Lifecycle |
| Category Key | EAC |
| Feature ID | EAC-003 |
| Status | 배포 완료 |
| Summary | Undo로 되돌린 최근 Entry 관련 액션을 다시 적용 |
| Related Region | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu | Edit |
| Shortcut | ⇧⌘Z |

## Preconditions

- <<AI>> 다시 적용 가능한 최근 Entry 액션이 존재하는 상태
- <<AI>> Entry 관련 작업 실행이 진행 중이지 않은 상태
## Edge Cases

- <<AI>> 외부 변경으로 재적용 전제가 깨진 경우
- <<AI>> Redo 대상 액션이 더 이상 유효하지 않은 경우

## Acceptance Criteria

- [ ] <<AI>> Redo 가능한 액션이 존재하는 상태일 때, 사용자가 해당 인터랙션을 호출하면, 가장 최근의 Redo 가능한 Entry 액션을 다시 적용함.
- [ ] <<AI>> Redo가 성공한 상태일 때, 시스템이 처리하면, Undo 스택을 갱신하고 관련 UI를 갱신함.
- [ ] <<AI>> Redo가 불가능한 상태일 때, 사용자가 해당 인터랙션을 호출하면, 아무 변화도 발생하지 않도록 함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `57`
