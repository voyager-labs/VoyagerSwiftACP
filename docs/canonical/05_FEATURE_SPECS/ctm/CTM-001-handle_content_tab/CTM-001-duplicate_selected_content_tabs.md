# Duplicate Selected Content Tabs

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CTM-001-duplicate_selected_content_tabs |
| Interaction Type | command |
| Feature | Handle Content Tab |
| Category Key | CTM |
| Feature ID | CTM-001 |
| Status | 준비 완료 |
| Summary | 선택한 Content Tab들을 각각 동일한 상태의 Content Tab으로 복제해 추가 |
| Related Region | file_manager_window.sidebar.sidebar_body.content_tabs_area |
| Menu | File |
| Shortcut | ⌘D |

## Preconditions

- 1개 이상의 Content Tab이 지정된 상태
## Edge Cases

- -

## Acceptance Criteria

- [ ] <<AI>> 하나 이상의 Content Tab이 선택된 상태에서 사용자가 해당 인터랙션을 호출하면, 각 선택된 탭 옆에 동일 상태의 복제 탭이 하나씩 생성되고 복제 대상과 동일한 세션 상태를 가짐.
- [ ] <<AI>> 매우 많은 탭이 선택된 상태에서 사용자가 해당 인터랙션을 호출하면, 복제가 순차적으로 진행되며 UI가 멈추지 않는 범위 내에서 진행 상황을 일정하게 반영하거나 필요한 경우 진행 중 표시를 제공함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `205`
