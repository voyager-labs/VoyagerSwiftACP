# Unpin Content Tab(s)

## Metadata

| Field            | Value                                                           |
| ---------------- | --------------------------------------------------------------- |
| Interaction ID   | CTM-003-unpin_content_tab_s                                     |
| Interaction Type | command                                                         |
| Feature          | Manage Pinned Content Tabs                                      |
| Category Key     | CTM                                                             |
| Feature ID       | CTM-003                                                         |
| Status           | 준비 완료                                                       |
| Summary          | 선택한 Pin 상태의 Content Tab(들)을 일반 Content Tab으로 되돌림 |
| Related Region   | file_manager_window.sidebar.sidebar_body.content_tabs_area      |
| Menu             | Context                                                         |
| Shortcut         | ⌘P                                                              |

## Preconditions

- 해당 Content Tab이 Pin된 상태
- 1개 이상의 Pinned Content Tab이 활성 상태거나 지정된 상태

## Edge Cases

-   -

## Acceptance Criteria

- [ ] <<AI>> 하나 이상의 Pin 상태 Content Tab이 선택된 상태에서 사용자가 해당 인터랙션을 호출하면,
      대상 탭들의 Pin 상태가 해제되고 일반 탭 영역으로 이동함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `214`
