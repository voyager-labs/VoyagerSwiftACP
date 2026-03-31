# Show Inspector Pane

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | FMW-002-show_inspector_pane |
| Interaction Type | command |
| Feature | Manage File Manager Window Panes |
| Category Key | FMW |
| Feature ID | FMW-002 |
| Status | 기획 완료 |
| Summary | Inspector Pane을 File Manager의 우측 영역에 고정되게 표시 |
| Related Region | file_manager_window.inspector_pane |
| Menu | View |
| Shortcut | - |

## Preconditions

- Inspector Pane이 숨김 상태
## Edge Cases

- -

## Acceptance Criteria

- [ ] Inspector Pane가 숨김 상태일 때, 사용자가 해당 인터랙션을 호출하면, Inspector Pane이 File Manager 우측 영역에 표시됨
- [ ] Inspector Pane이 표시될 때, 숨긴 시점의 Pane Mode가 Chat Pane이 아니라면, 해당 Pane Mode로 렌더링됨

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `14`
