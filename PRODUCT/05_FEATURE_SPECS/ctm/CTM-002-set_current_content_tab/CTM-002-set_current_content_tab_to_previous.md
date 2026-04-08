# Set Current Content Tab to Previous

## Metadata

| Field            | Value                                                                     |
| ---------------- | ------------------------------------------------------------------------- |
| Interaction ID   | CTM-002-set_current_content_tab_to_previous                               |
| Interaction Type | command                                                                   |
| Feature          | Set Current Content Tab                                                   |
| Category Key     | CTM                                                                       |
| Feature ID       | CTM-002                                                                   |
| Status           | 준비 완료                                                                 |
| Summary          | Content Tab List 상 현재 Content Tab보다 이전 위치의 Content Tab으로 전환 |
| Related Region   | file_manager_window.sidebar.sidebar_body.content_tabs_area                |
| Menu             | -                                                                         |
| Shortcut         | ⌘⇧[                                                                       |

## Preconditions

- 2개 이상의 Content Tab이 열린 상태

## Edge Cases

- 현재 Content Tab이 Tab List 상 처음에 위치해 있는 경우

## Acceptance Criteria

- [ ] <<AI>> Content Tab이 두 개 이상 열려 있고 현재 탭이 첫 번째가 아닐 때, 사용자가 해당
      인터랙션을 호출하면, Content Tab List에서 바로 이전 위치의 탭이 활성화됨.
- [ ] <<AI>> 현재 탭이 첫 번째 탭인 상태에서 사용자가 해당 인터랙션을 호출하면, 활성 탭이 변경되지
      않거나 순환 동작을 정의한 경우 첫 번째 탭이 유지됨.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `206`
