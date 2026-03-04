# Duplicate Entry(ies)

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EAC-002-duplicate_entry_ies |
| Interaction Type | command |
| Feature | Organize Entries |
| Category Key | EAC |
| Feature ID | EAC-002 |
| Status | 배포 완료 |
| Summary | 선택한 Entry의 복제본을 동일 위치에 생성 |
| Related Region | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu | File |
| Shortcut | ⌘D |

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태
- <<AI>> 선택된 Entry가 위치한 디렉토리에 대해 쓰기 권한이 있는 상태
## Edge Cases

- <<AI>> 대상 위치에 쓰기 권한이 없어 복제가 불가능한 경우
- <<AI>> 대용량/다수 항목으로 복제 시간이 길어 진행 표시가 필요한 경우
- <<AI>> 복제본 이름 충돌이 발생하는 경우

## Acceptance Criteria

- [ ] <<AI>> 복제 가능한 상태일 때, 사용자가 해당 인터랙션을 호출하면, 선택한 Entry의 복제본을 동일 위치에 생성함.
- [ ] <<AI>> 이름 충돌이 발생하는 상태일 때, 시스템이 복제본을 생성하면, 충돌을 회피하는 이름 규칙으로 복제본 이름을 결정함.
- [ ] <<AI>> 복제 불가한 상태일 때, 사용자가 해당 인터랙션을 호출하면, 복제를 수행하지 않고 실패 사유를 사용자에게 안내함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `47`
