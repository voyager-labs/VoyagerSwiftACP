# Move Content Tab to Another File Manager Window

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CTM-001-move_content_tab_to_another_file_manager_window |
| Interaction Type | command |
| Feature | Handle Content Tab |
| Category Key | CTM |
| Feature ID | CTM-001 |
| Status | 준비 완료 |
| Summary | 해당 Content Tab을 다른 File Manager로 배치 |
| Related Region | file_manager_window.sidebar.sidebar_body.content_tabs_area |
| Menu | - |
| Shortcut | - |

## Preconditions

- 2개 이상의 File Manager Window가 열린 상태
## Edge Cases

- -

## Acceptance Criteria

- [ ] <<AI>> 둘 이상의 File Manager Window가 열려 있고 대상 창이 유효한 상태일 때, 사용자가 해당 인터랙션을 호출하면, 선택된 Content Tab이 지정된 다른 File Manager Window의 Tab List로 이동하고 원래 창에서는 제거됨.
- [ ] <<AI>> 이동 대상 File Manager Window가 이동 처리 중 닫힌 경우, 사용자가 해당 인터랙션을 호출하면, 탭 이동을 수행하지 않고 원래 창 상태를 유지하거나 다른 유효한 대상이 없는 경우 오류를 표시함.
- [ ] <<AI>> 이동 대상 창에 동일 세션의 탭이 이미 존재하는 상태에서 사용자가 해당 인터랙션을 호출하면, 중복 세션 처리 정책(예: 중복 허용 또는 기존 탭 활성화)을 따르고 그 결과를 UI에 일관되게 반영함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `198`
