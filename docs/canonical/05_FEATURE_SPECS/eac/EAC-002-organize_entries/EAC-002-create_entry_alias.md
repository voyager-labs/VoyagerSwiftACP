# Create Entry Alias

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EAC-002-create_entry_alias |
| Interaction Type | command |
| Feature | Organize Entries |
| Category Key | EAC |
| Feature ID | EAC-002 |
| Status | 배포 완료 |
| Summary | 선택한 Entry에 대한 Alias(바로가기)를 생성 |
| Related Region | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu | File |
| Shortcut | ⌃⌘A |

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태
- <<AI>> Alias를 생성할 위치에 대해 쓰기 권한이 있는 상태
## Edge Cases

- <<AI>> Alias 파일 이름 충돌이 발생하는 경우
- <<AI>> 선택된 Entry가 삭제되어 원본 참조가 불가능한 경우
- <<AI>> 스토리지/파일 시스템 제약으로 Alias 생성을 지원하지 않는 경우

## Acceptance Criteria

- [ ] <<AI>> Alias 생성이 가능한 상태일 때, 사용자가 해당 인터랙션을 호출하면, 선택한 Entry를 가리키는 Alias를 생성함.
- [ ] <<AI>> 이름 충돌이 발생하는 상태일 때, 시스템이 Alias를 생성하면, 충돌을 회피하는 이름 규칙으로 Alias 이름을 결정함.
- [ ] <<AI>> Alias 생성이 불가능한 상태일 때, 사용자가 해당 인터랙션을 호출하면, Alias를 생성하지 않고 실패 사유를 사용자에게 안내함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `49`
