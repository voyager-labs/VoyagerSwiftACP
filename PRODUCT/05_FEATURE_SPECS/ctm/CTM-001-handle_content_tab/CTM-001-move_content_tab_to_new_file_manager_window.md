# Move Content Tab to New File Manager Window

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CTM-001-move_content_tab_to_new_file_manager_window |
| Interaction Type | command |
| Feature | Handle Content Tab |
| Category Key | CTM |
| Feature ID | CTM-001 |
| Status | 준비 완료 |
| Summary | 해당 Contnet Tab을 새 File Manager Window로 분리해 별도 창으로 이동 |
| Related Region | file_manager_window.sidebar.sidebar_body.content_tabs_area |
| Menu | Context |
| Shortcut | - |

## Preconditions

- -
## Edge Cases

- 현재 File Manager Window에 하나뿐인 Content Tab인 상태에서 이동하는 경우.
- 새 창 생성 시 시스템 리소스 부족으로 인해 창 생성이 실패하는 경우.

## Acceptance Criteria

- [ ] <<AI>> 이동할 Content Tab이 하나 이상 있고 새 창을 생성할 수 있는 상태일 때, 사용자가 해당 인터랙션을 호출하면, 새 File Manager Window가 생성되고 대상 탭이 새 창으로 이동하며 원래 창에서는 제거됨.
- [ ] <<AI>> 현재 File Manager Window에 하나의 탭만 남은 상태에서 사용자가 해당 인터랙션을 호출하면, 정의된 정책(예: 원래 창을 닫고 새 창만 유지)을 따르며 두 창 상태가 일관되게 유지됨.
- [ ] <<AI>> 시스템 리소스 부족으로 인해 새 창을 생성할 수 없는 상태에서 사용자가 해당 인터랙션을 호출하면, 탭 이동이 수행되지 않고 오류 또는 경고를 표시함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `197`
