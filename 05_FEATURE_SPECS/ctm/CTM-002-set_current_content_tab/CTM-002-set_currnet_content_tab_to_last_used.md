# Set Currnet Content Tab to Last Used

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CTM-002-set_currnet_content_tab_to_last_used |
| Interaction Type | command |
| Feature | Set Current Content Tab |
| Category Key | CTM |
| Feature ID | CTM-002 |
| Status | 준비 완료 |
| Summary | 최근 Content Tab 전환 순서 기준 마지막으로 전환한 Content Tab으로 전환 |
| Related Region | file_manager_window.sidebar.sidebar_body.content_tabs_area |
| Menu | - |
| Shortcut | ⌃⇥ |

## Preconditions

- 2개 이상의 Content Tab이 열린 상태
- 최근 Content Tab 전환 이력이 존재하는 상태
## Edge Cases

- -

## Acceptance Criteria

- [ ] <<AI>> 최근 Content Tab 전환 이력이 존재할 때, 사용자가 해당 인터랙션을 호출하면, 전환 이력 기준 직전에 사용한 Content Tab이 활성화되어 두 탭 간 빠르게 전환됨.
- [ ] <<AI>> 전환 이력이 초기화된 상태에서 사용자가 해당 인터랙션을 호출하면, 활성 탭이 변경되지 않고 조용히 무시되거나 이력이 없음을 알리는 피드백을 표시함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `209`
