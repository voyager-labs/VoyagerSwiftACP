# Draw Hidden Sidebar

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | FMW-002-draw_hidden_sidebar |
| Interaction Type | command |
| Feature | Manage File Manager Window Panes |
| Category Key | FMW |
| Feature ID | FMW-002 |
| Status | 기획 완료 |
| Summary | 숨겨진 Sidebar를 File Manager의 좌측 영역에 일시적으로 표시 |
| Related Region | file_manager_window.sidebar |
| Menu | - |
| Shortcut | - |

## Preconditions

- Sidebar가 숨김 상태
## Edge Cases

- 사용자가 Sidebar 내부 요소와 인터랙션하는 중 인식 범위를 벗어나는 경우

## Acceptance Criteria

- [ ] Sidebar가 숨김 상태일 때, 사용자가 해당 인터랙션을 호출하면, Sidebar가 좌측에서 일시적으로 슬라이드 인되어 표시되고 사용자 포인터나 포커스가 Sidebar 영역을 벗어나면 자동으로 다시 숨겨짐
- [ ] Sidebar가 숨김 상태일 때, 사용자가 해당 인터랙션을 반복 호출하면, Sidebar 임시 표시 상태가 갱신되거나 유지되어 사용자가 내용을 확인할 수 있음

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `13`
