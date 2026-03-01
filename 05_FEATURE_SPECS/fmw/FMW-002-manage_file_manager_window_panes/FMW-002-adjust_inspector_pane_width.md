# Adjust Inspector Pane Width

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | FMW-002-adjust_inspector_pane_width |
| Interaction Type | input |
| Feature | Manage File Manager Window Panes |
| Category Key | FMW |
| Feature ID | FMW-002 |
| Status | 기획 완료 |
| Summary | Inspector Pane의 Width를 최소-최대 범위 내에서 조정 |
| Related Region | file_manager_window.inspector_pane |
| Menu | - |
| Shortcut | - |

## Preconditions

- Inspector Pane이 표시 상태
## Edge Cases

- 최소 너비 이하로 조정되는 경우
- 최대 너비 이상으로 조정되는 경우
- 너비 조정 중 Hide Inspector Pane이 호출되는 경우

## Acceptance Criteria

- [ ] Inspector Pane이 표시 상태일 때, 사용자가 해당 인터랙션을 호출하면, Inspector Pane Width가 정의된 최소-최대 범위 내에서만 변경됨
- [ ] Inspector Pane 너비를  줄이려 할 때, 최소 허용값 이하로 줄이려 한다면, Inspector Pane Width가 최소값에서 멈춤
- [ ] Inspector Pane 너비를 늘리려 할 때,  최대 허용값 이상으로 늘리려 한다면, Inspector Pane Width가 최대값에서 더 이상 증가하지 않음

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `16`
