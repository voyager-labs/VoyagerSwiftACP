# Show Sidebar

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | FMW-002-show_sidebar |
| Interaction Type | command |
| Feature | Manage File Manager Window Panes |
| Category Key | FMW |
| Feature ID | FMW-002 |
| Status | 배포 완료 |
| Summary | Sidebar를 File Manager의 좌측 영역에 고정되게 표시 |
| Related Region | file_manager_window.sidebar |
| Menu | View |
| Shortcut | ⌘⌃S |

## Preconditions

- Sidebar가 숨김 상태
## Edge Cases

- 현재 창 너비가 표시되는 Sidebar의 설정된 너비보다 작은 경우

## Acceptance Criteria

- [ ] Sidebar가 숨김 상태이고 창 너비가 Sidebar를 표시하기에 충분할 때, 사용자가 해당 인터랙션을 호출하면, Sidebar가 File Manager 좌측 영역에 기본 너비로 고정되어 표시됨
- [ ] 창 너비가 Sidebar 최소 너비보다 작은 상태일 때, 사용자가 해당 인터랙션을 호출하면, Sidebar의 최소 너비만큼 Window의 너비를 늘림

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `10`
