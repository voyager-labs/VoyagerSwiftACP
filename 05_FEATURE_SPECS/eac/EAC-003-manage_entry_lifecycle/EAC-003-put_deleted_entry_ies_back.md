# Put Deleted Entry(ies) Back

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EAC-003-put_deleted_entry_ies_back |
| Interaction Type | command |
| Feature | Manage Entry Lifecycle |
| Category Key | EAC |
| Feature ID | EAC-003 |
| Status | 취소 |
| Summary | 선택한 휴지통의 Entry를 휴지통으로 가기 이전 경로로 복원 |
| Related Region | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu | File |
| Shortcut | ⌘⌫ |

## Preconditions

- 휴지통 컨텍스트에서 하나 이상의 Entry가 선택된 상태
- 선택된 Entry의 삭제 이전 경로 정보를 확보한 상태
## Edge Cases

- 삭제 이전 경로가 더 이상 존재하지 않는 경우
- 삭제 이전 위치에 동일 이름 Entry가 존재해 충돌이 발생하는 경우
- 원래 위치 권한 부족으로 복원이 불가능한 경우

## Acceptance Criteria

- [ ] -

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `54`
