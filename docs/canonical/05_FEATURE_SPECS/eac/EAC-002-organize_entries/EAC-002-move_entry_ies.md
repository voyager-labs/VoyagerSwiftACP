# Move Entry(ies)

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EAC-002-move_entry_ies |
| Interaction Type | command |
| Feature | Organize Entries |
| Category Key | EAC |
| Feature ID | EAC-002 |
| Status | 배포 완료 |
| Summary | 선택한 Entry를 지정한 대상 디렉토리로 이동 |
| Related Region | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu | File |
| Shortcut | - |

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태
- <<AI>> 이동 대상 디렉토리가 지정된 상태
- <<AI>> 대상 디렉토리에 대해 쓰기 권한이 있는 상태
## Edge Cases

- <<AI>> 대상 디렉토리가 현재 위치와 동일한 경우
- <<AI>> 폴더를 자기 자신 또는 자기 하위 디렉토리로 이동하려는 경우
- <<AI>> 이름 충돌 또는 권한 문제로 부분 성공이 발생하는 경우
- <<AI>> 볼륨 간 이동으로 복사+원본 삭제가 필요한 경우

## Acceptance Criteria

- [ ] <<AI>> 이동 대상 디렉토리가 지정된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 선택한 Entry를 대상 디렉토리로 이동함.
- [ ] <<AI>> 볼륨 간 이동이 필요한 상태일 때, 시스템이 이동을 수행하면, 시스템 제약에 맞게 안전하게 처리하고 최종적으로 대상에 존재하도록 함.
- [ ] <<AI>> 이동이 부분 성공하는 상태일 때, 시스템이 이동을 수행하면, 성공/실패 항목을 구분해 결과와 사유를 사용자에게 안내함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `48`
