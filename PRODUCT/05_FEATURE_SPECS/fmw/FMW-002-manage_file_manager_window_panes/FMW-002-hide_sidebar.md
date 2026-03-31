# Hide Sidebar

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | FMW-002-hide_sidebar |
| Interaction Type | command |
| Feature | Manage File Manager Window Panes |
| Category Key | FMW |
| Feature ID | FMW-002 |
| Status | 배포 완료 |
| Summary | Sidebar를 File Manager에서 보이지 않게 숨김 |
| Related Region | file_manager_window.sidebar |
| Menu | View |
| Shortcut | ⌘⌃S |

## Preconditions

- Sidebar가 표시 상태
## Edge Cases

- 사용자가 Sidebar 내부 요소와 인터랙션 중 호출되는 경우

## Acceptance Criteria

- [ ] Sidebar가 표시 상태일 때, 사용자가 해당 인터랙션을 호출하면, Sidebar가 숨김 상태로 전환되고 Content Pane이 좌측으로 확장됨
- [ ] 사용자가 Sidebar 내부 요소와 인터랙션 중일 때, 사용자가 해당 인터랙션을 호출하면, 현재 상호작용을 안전하게 종료한 뒤 후속 처리를 함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `11`
