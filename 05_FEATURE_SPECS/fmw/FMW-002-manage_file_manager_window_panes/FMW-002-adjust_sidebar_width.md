# Adjust Sidebar Width

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | FMW-002-adjust_sidebar_width |
| Interaction Type | input |
| Feature | Manage File Manager Window Panes |
| Category Key | FMW |
| Feature ID | FMW-002 |
| Status | 배포 완료 |
| Summary | Sidebar의 Width를 최소-최대 범위 내에서 조정 |
| Related Region | file_manager_window.sidebar |
| Menu | - |
| Shortcut | - |

## Preconditions

- Sidebar가 표시 상태
## Edge Cases

- 사용자가 최소 너비 허용값 이하로 조정하려는 경우
- 사용자가 최대 너비 허용값 이상으로 조정하려는 경우
- 너비 조정 중 Hide Sidebar가 호출되는 경우

## Acceptance Criteria

- [ ] Sidebar가 표시 상태일 때, 사용자가 해당 인터랙션을 호출하면, Sidebar Width가 정의된 최소-최대 범위 내에서만 변경됨
- [ ] Sidebar 너비를 최소 허용값 이하로 줄이려는 상태에서 사용자가 해당 인터랙션을 호출하면, Hide Sidebar 인터랙션을 호출함
- [ ] Sidebar 너비를 늘리려 할 때, 특정한 값에 도달한다면, 해당 값에서 더 이상 증가하지 않음

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `12`
