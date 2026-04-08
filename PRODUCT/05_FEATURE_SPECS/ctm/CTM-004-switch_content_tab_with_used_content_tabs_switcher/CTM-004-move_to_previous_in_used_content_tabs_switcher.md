# Move to Previous in Used Content Tabs Switcher

## Metadata

| Field            | Value                                                                         |
| ---------------- | ----------------------------------------------------------------------------- |
| Interaction ID   | CTM-004-move_to_previous_in_used_content_tabs_switcher                        |
| Interaction Type | command                                                                       |
| Feature          | Switch Content Tab with Used Content Tabs Switcher                            |
| Category Key     | CTM                                                                           |
| Feature ID       | CTM-004                                                                       |
| Status           | 준비 완료                                                                     |
| Summary          | Used Content Tabs Switcher에서 전환할 Content Tab 선택 포커스를 이전으로 이동 |
| Related Region   | file_manager_window.sidebar.sidebar_body.content_tabs_area                    |
| Menu             | -                                                                             |
| Shortcut         | ⌃⇧⇥                                                                           |

## Preconditions

- Used Content Tabs Switcher가 화면에 표시된 상태

## Edge Cases

- 현재 지정된 탭이 Used Content Tabs Switcher List 상 처음에 위치해 있는 경우

## Acceptance Criteria

- [ ] <<AI>> Used Content Tabs Switcher가 표시된 상태이고 이전 항목이 존재할 때, 사용자가 해당
      인터랙션을 호출하면, 포커스가 바로 이전 Content Tab으로 이동함.
- [ ] <<AI>> 이전 항목이 존재하지 않는 상태에서 사용자가 해당 인터랙션을 호출하면, 포커스가 첫 번째
      탭에 머무르거나 순환 설정에 따라 마지막 탭으로 이동함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `212`
