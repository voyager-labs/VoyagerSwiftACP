# Copy URL(s) of Entry(ies)

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EAC-006-copy_urls_of_entry_ies |
| Interaction Type | command |
| Feature | Copy Entry References |
| Category Key | EAC |
| Feature ID | EAC-006 |
| Status | 배포 완료 |
| Summary | 선택한 Entry의 파일 시스템 URL을 클립보드에 복사 |
| Related Region | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu | Edit |
| Shortcut | ⌥⌘U |

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태
## Edge Cases

- <<AI>> 파일명/경로에 특수 문자가 포함되어 URL 인코딩이 필요한 경우
- <<AI>> 일부 Entry가 유효한 URL로 변환 불가능한 경우

## Acceptance Criteria

- [ ] <<AI>> 하나 이상의 Entry가 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 선택한 Entry의 파일 시스템 URL을 클립보드에 복사함.
- [ ] <<AI>> 다중 선택 상태일 때, 시스템이 복사를 수행하면, 각 URL을 줄바꿈으로 구분해 저장함.
- [ ] <<AI>> 일부 URL을 만들 수 없는 상태일 때, 시스템이 복사를 수행하면, 복사 가능한 항목만 포함하고 제외된 대상과 사유를 사용자에게 안내함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `65`
