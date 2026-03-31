# Move Entry(ies) to Trash

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EAC-003-move_entry_ies_to_trash |
| Interaction Type | command |
| Feature | Manage Entry Lifecycle |
| Category Key | EAC |
| Feature ID | EAC-003 |
| Status | 배포 완료 |
| Summary | 선택한 Entry를 휴지통으로 이동 |
| Related Region | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu | File |
| Shortcut | ⌘⌫ |

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태
- <<AI>> 선택된 Entry를 휴지통으로 이동할 수 있는 상태
## Edge Cases

- <<AI>> 선택된 Entry가 잠겨 있거나 권한 부족으로 이동 불가능한 경우
- <<AI>> 클라우드/네트워크 지연으로 이동 반영이 지연되는 경우
- <<AI>> 일부만 이동 가능해 부분 성공이 발생하는 경우

## Acceptance Criteria

- [ ] <<AI>> 휴지통 이동이 가능한 상태일 때, 사용자가 해당 인터랙션을 호출하면, 선택한 Entry를 휴지통으로 이동함.
- [ ] <<AI>> 휴지통 이동이 수행된 상태일 때, 시스템이 처리하면, 복원을 위해 삭제 이전 경로 정보를 기록함.
- [ ] <<AI>> 일부만 이동 가능한 상태일 때, 시스템이 이동을 수행하면, 성공/실패 항목과 사유를 사용자에게 안내함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `52`
