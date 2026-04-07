# Pin Content Tab(s)

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CTM-003-pin_content_tab_s |
| Interaction Type | command |
| Feature | Manage Pinned Content Tabs |
| Category Key | CTM |
| Feature ID | CTM-003 |
| Status | 준비 완료 |
| Summary | 선택한 Content Tab(들)을 Pin 상태로 전환하여 세션 종료 후에도 유지 |
| Related Region | file_manager_window.sidebar.sidebar_body.content_tabs_area |
| Menu | Context |
| Shortcut | ⌘P |

## Preconditions

- 1개 이상의 Content Tab이 활성 상태 거나 지정된 상태
- 해당 Content Tab이 Pin되지 않은 상태
## Edge Cases

- 이미 Pin 상태인 Content Tab에 대해 시도하는 경우

## Acceptance Criteria

- [ ] <<AI>> 하나 이상의 Content Tab이 선택된 상태에서 사용자가 해당 인터랙션을 호출하면, 대상 탭들이 Pin 상태로 전환되고 Pinned 영역에 고정되어 세션 종료 후 재실행 시에도 복원됨.
- [ ] <<AI>> 이미 Pin 상태인 Content Tab에 대해 사용자가 해당 인터랙션을 호출하면, Pin 상태가 변경되지 않고 UI가 그대로 유지되거나 중복 동작이 없는 토글 정책에 따라 처리됨.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `213`
