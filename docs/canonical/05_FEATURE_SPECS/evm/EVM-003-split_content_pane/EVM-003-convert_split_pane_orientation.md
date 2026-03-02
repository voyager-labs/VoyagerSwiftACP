# Convert Split Pane Orientation

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EVM-003-convert_split_pane_orientation |
| Interaction Type | command |
| Feature | Split Content Pane |
| Category Key | EVM |
| Feature ID | EVM-003 |
| Status | 기획 완료 |
| Summary | <<AI>> 기존 분할된 Content Pane의 방향을 수직↔수평으로 전환합니다. |
| Related Region | file_manager_window.content_pane |
| Menu | - |
| Shortcut | - |

## Preconditions

- <<AI>> Content Pane이 이미 분할 상태.
- <<AI>> 레이아웃 변경을 위한 최소 폭/높이가 확보된 상태.
## Edge Cases

- <<AI>> 새 방향에서 각 Pane 최소 크기를 충족하지 못하는 경우 비율 재조정 또는 전환 불가 안내가 필요.
- <<AI>> 고정된 UI(예: 최소 폭을 가진 Sidebar/Inspector)로 인해 균등 분할 불가한 경우.

## Acceptance Criteria

- [ ] <<AI>> 사용자가 인터랙션을 호출하면 분할 방향이 수직↔수평으로 전환됨.
- [ ] <<AI>> 기존 두 Pane의 콘텐츠/스크롤/선택 상태는 유지되며, 디바이더 위치는 가능한 범위에서 기존 비율을 반영해 재배치됨.
- [ ] <<AI>> 제약으로 균등 분할이 불가하면 합리적 비율로 자동 조정하거나 안내를 표시함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `35`
