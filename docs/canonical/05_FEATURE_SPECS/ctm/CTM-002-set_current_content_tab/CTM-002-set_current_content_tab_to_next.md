# Set Current Content Tab to Next

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CTM-002-set_current_content_tab_to_next |
| Interaction Type | command |
| Feature | Set Current Content Tab |
| Category Key | CTM |
| Feature ID | CTM-002 |
| Status | 준비 완료 |
| Summary | Content Tab List 상 현재 Content Tab보다 다음 위치의 Content Tab으로 전환 |
| Related Region | file_manager_window.sidebar.sidebar_body.content_tabs_area |
| Menu | - |
| Shortcut | ⌘⇧] |

## Preconditions

- 2개 이상의 Content Tab이 열린 상태
## Edge Cases

- 현재 Content Tab이 Tab List 상 마지막에 위치해 있는 경우

## Acceptance Criteria

- [ ] <<AI>> 지정한 번호 위치에 해당하는 Content Tab이 존재할 때, 사용자가 해당 인덱스에 대한 인터랙션을 호출하면, 그 번호에 해당하는 Content Tab이 활성화됨.
- [ ] <<AI>> 지정한 번호 위치에 해당하는 Content Tab이 존재하지 않을 때, 사용자가 해당 인터랙션을 호출하면, 활성 탭이 변경되지 않고 조용히 무시되거나 정의된 피드백을 표시함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `207`
