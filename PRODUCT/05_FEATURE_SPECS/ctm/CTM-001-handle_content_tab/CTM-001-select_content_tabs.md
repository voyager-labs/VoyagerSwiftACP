# Select Content Tabs

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CTM-001-select_content_tabs |
| Interaction Type | command |
| Feature | Handle Content Tab |
| Category Key | CTM |
| Feature ID | CTM-001 |
| Status | 준비 완료 |
| Summary | Sidebar의 Content Tab List에서 하나 이상의 Content Tab을 선택 |
| Related Region | file_manager_window.sidebar.sidebar_body.content_tabs_area |
| Menu | - |
| Shortcut | - |

## Preconditions

- -
## Edge Cases

- -

## Acceptance Criteria

- [ ] <<AI>> Sidebar에 Content Tab List가 표시될 때, 사용자가 해당 인터랙션을 호출하면, 클릭 또는 보조키 조합에 따라 하나 이상의 Content Tab이 선택 상태로 하이라이트됨.
- [ ] <<AI>> 사용자가 잘못된 범위를 선택했다가 다시 인터랙션을 호출하면, 선택 상태가 그에 맞게 즉시 갱신되어 이후 다중 탭 관련 동작의 대상이 일관되게 유지됨.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `201`
