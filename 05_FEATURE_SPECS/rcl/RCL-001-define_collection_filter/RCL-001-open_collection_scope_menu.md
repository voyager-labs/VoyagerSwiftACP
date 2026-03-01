# Open Collection Scope Menu

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-001-open_collection_scope_menu |
| Interaction Type | command |
| Feature | Define Collection Filter |
| Category Key | RCL |
| Feature ID | RCL-001 |
| Status | 배포 완료 |
| Summary | 스코프 드롭다운 메뉴를 열어 컨디션이 적용될 스코프를 선택할 수 있는 옵션을 제공 |
| Related Region | file_manager_window.content_pane.content_header.collection_fillter_composer |
| Menu | - |
| Shortcut | - |

## Preconditions

- Collection Filter Composer가 열린 상태
## Edge Cases

- 스코프 메뉴가 이미 열린 상태에서 호출되는 경우

## Acceptance Criteria

- [ ] 사용자가 해당 인터랙션을 호출했을 때, 스코프 메뉴가 표시되었다면, 선택 가능한 모든 디렉토리 목록이 노출됨
- [ ] 스코프 메뉴가 이미 열린 상태일 때, 사용자가 해당 인터랙션을 호출하면, 열린 상태를 유지함 (닫기 위해선 해당 요소 바깥을 클릭)

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `113`
