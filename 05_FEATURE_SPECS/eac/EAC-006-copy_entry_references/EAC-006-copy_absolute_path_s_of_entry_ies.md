# Copy Absolute Path(s) of Entry(ies)

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EAC-006-copy_absolute_path_s_of_entry_ies |
| Interaction Type | command |
| Feature | Copy Entry References |
| Category Key | EAC |
| Feature ID | EAC-006 |
| Status | 배포 완료 |
| Summary | 선택한 Entry의 절대 경로를 클립보드에 복사 |
| Related Region | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu | Edit |
| Shortcut | ⌥⌘C |

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태
## Edge Cases

- <<AI>> 일부 Entry의 경로를 해석할 수 없는 경우
- <<AI>> 선택된 Entry 수가 많아 문자열 생성이 지연되는 경우

## Acceptance Criteria

- [ ] <<AI>> 하나 이상의 Entry가 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 선택한 Entry의 절대 경로를 클립보드에 복사함.
- [ ] <<AI>> 다중 선택 상태일 때, 시스템이 복사를 수행하면, 각 경로를 줄바꿈으로 구분해 저장함.
- [ ] <<AI>> 일부 경로를 만들 수 없는 상태일 때, 시스템이 복사를 수행하면, 복사 가능한 항목만 포함하고 제외된 대상과 사유를 사용자에게 안내함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `63`
