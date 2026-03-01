# Close Other Content Tabs

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CTM-001-close_other_content_tabs |
| Interaction Type | command |
| Feature | Handle Content Tab |
| Category Key | CTM |
| Feature ID | CTM-001 |
| Status | 준비 완료 |
| Summary | 현재 Content Tab을 제외한 나머지 Content Tab을 모두 닫음 |
| Related Region | file_manager_window.sidebar.sidebar_body.content_tabs_area |
| Menu | Context |
| Shortcut | - |

## Preconditions

- 2개 이상의 Content Tab이 열린 상태
## Edge Cases

- 닫으려는 Content Tab에 진행 중인 상태의 작업이 있는 경우

## Acceptance Criteria

- [ ] <<AI>> Content Tab이 2개 이상 열려 있고 닫히는 탭 중 저장되지 않은 변경 사항이 없을 때, 사용자가 해당 인터랙션을 호출하면, 현재 활성 탭을 제외한 나머지 탭이 모두 닫히고 현재 탭은 그대로 유지됨.
- [ ] <<AI>> 닫히는 탭들 중 하나 이상에 저장되지 않은 변경 사항이 있을 때, 사용자가 해당 인터랙션을 호출하면, 일괄 닫기 여부를 묻는 확인 대화를 표시하고 사용자가 닫기를 선택하면 모든 대상 탭이 닫힘.
- [ ] <<AI>> 닫히는 탭들 중 Pinned Content Tab이 포함된 경우, 사용자가 해당 인터랙션을 호출하면, 정의된 정책(예: Pinned 탭은 유지)을 따르며 실제로 닫힌 탭과 유지된 탭이 UI에 일관되게 반영됨.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `195`
