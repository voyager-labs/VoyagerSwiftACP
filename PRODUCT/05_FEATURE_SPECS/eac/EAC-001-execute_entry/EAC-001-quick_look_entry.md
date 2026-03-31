# Quick Look Entry

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EAC-001-quick_look_entry |
| Interaction Type | command |
| Feature | Execute Entry |
| Category Key | EAC |
| Feature ID | EAC-001 |
| Status | 배포 완료 |
| Summary | 선택한 Entry의 내용을 볼 수 있는 Quick Look을 실행 |
| Related Region | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu | View |
| Shortcut | Space, ⌘Y |

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태
- <<AI>> Quick Look을 표시할 수 있는 UI 상태인 상태
## Edge Cases

- <<AI>> 선택된 Entry가 Quick Look 미지원 포맷이거나 프리뷰 생성에 실패하는 경우
- <<AI>> 클라우드/네트워크 지연으로 Entry가 로컬에 없어 즉시 프리뷰할 수 없는 경우
- <<AI>> Quick Look이 이미 표시 중인 경우

## Acceptance Criteria

- [ ] <<AI>> 하나 이상의 Entry가 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, Quick Look을 표시하고 선택된 Entry의 내용을 보여줌.
- [ ] <<AI>> Quick Look이 이미 표시 중인 상태일 때, 사용자가 해당 인터랙션을 호출하면, Quick Look을 토글하거나 현재 선택 상태에 맞게 표시 대상을 갱신함.
- [ ] <<AI>> 프리뷰 생성이 실패하는 상태일 때, 사용자가 해당 인터랙션을 호출하면, “미리보기 불가” 상태를 표시하고 실패 사유를 확인 가능하게 함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `42`
