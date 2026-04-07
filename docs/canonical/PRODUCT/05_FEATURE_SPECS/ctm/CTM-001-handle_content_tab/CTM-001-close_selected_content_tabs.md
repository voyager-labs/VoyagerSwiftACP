# Close Selected Content Tabs

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CTM-001-close_selected_content_tabs |
| Interaction Type | command |
| Feature | Handle Content Tab |
| Category Key | CTM |
| Feature ID | CTM-001 |
| Status | 준비 완료 |
| Summary | 선택한 Content Tab들을 닫음 |
| Related Region | file_manager_window.sidebar.sidebar_body.content_tabs_area |
| Menu | Context |
| Shortcut | ⌘W |

## Preconditions

- 1개 이상의 Content Tab이 지정된 상태
## Edge Cases

- 선택된 탭 전체가 해당 File Manager Window의 모든 탭인 경우.
- 선택된 탭들 중 저장되지 않은 변경 사항이 있는 탭이 포함된 경우.

## Acceptance Criteria

- [ ] <<AI>> 하나 이상의 Content Tab이 선택된 상태이고 저장되지 않은 변경 사항이 없는 경우, 사용자가 해당 인터랙션을 호출하면, 선택된 모든 탭이 닫히고 남아 있는 탭 중 하나가 활성화됨.
- [ ] <<AI>> 선택된 탭들 중 하나 이상에 저장되지 않은 변경 사항이 있는 경우, 사용자가 해당 인터랙션을 호출하면, 일괄 닫기 여부를 묻는 확인 대화를 표시하고 사용자가 닫기를 선택하면 대상 탭들이 모두 닫힘.
- [ ] <<AI>> 선택된 탭들이 현재 창의 모든 탭인 경우, 사용자가 해당 인터랙션을 호출하면, 정의된 정책(예: 빈 탭 생성 또는 창 닫기)에 따라 동작하고 그 결과가 UI에 일관되게 반영됨.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `202`
