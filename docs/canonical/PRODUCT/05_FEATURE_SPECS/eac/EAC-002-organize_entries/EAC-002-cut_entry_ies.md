# Cut Entry(ies)

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EAC-002-cut_entry_ies |
| Interaction Type | command |
| Feature | Organize Entries |
| Category Key | EAC |
| Feature ID | EAC-002 |
| Status | 배포 완료 |
| Summary | 선택한 Entry를 이동을 위한 잘라내기 상태로 클립보드에 저장 |
| Related Region | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu | Edit |
| Shortcut | ⌘X |

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태
## Edge Cases

- <<AI>> 선택된 Entry가 이동 불가(권한/시스템 보호/읽기 전용 볼륨)일 가능성이 있는 경우
- <<AI>> 기존 클립보드에 다른 복사/잘라내기 대상이 저장되어 있는 경우

## Acceptance Criteria

- [ ] <<AI>> 하나 이상의 Entry가 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 선택한 Entry 참조를 클립보드에 “이동(잘라내기)” 의도로 저장함.
- [ ] <<AI>> 기존 클립보드에 대상이 존재하는 상태일 때, 사용자가 해당 인터랙션을 호출하면, 이전 클립보드 대상을 새 대상으로 대체함.
- [ ] <<AI>> Entry가 선택되지 않은 상태일 때, 사용자가 해당 인터랙션을 호출하면, 클립보드 상태를 변경하지 않도록 함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `45`
