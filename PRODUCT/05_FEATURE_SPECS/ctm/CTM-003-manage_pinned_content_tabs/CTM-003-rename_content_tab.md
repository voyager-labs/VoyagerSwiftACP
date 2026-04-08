# Rename Content Tab

## Metadata

| Field            | Value                                                      |
| ---------------- | ---------------------------------------------------------- |
| Interaction ID   | CTM-003-rename_content_tab                                 |
| Interaction Type | input                                                      |
| Feature          | Manage Pinned Content Tabs                                 |
| Category Key     | CTM                                                        |
| Feature ID       | CTM-003                                                    |
| Status           | 아이디어                                                   |
| Summary          | 해당 Content Tab의 이름을 수정                             |
| Related Region   | file_manager_window.sidebar.sidebar_body.content_tabs_area |
| Menu             | -                                                          |
| Shortcut         | -                                                          |

## Preconditions

- 이름을 변경할 Content Tab이 활성 상태거나 지정된 상태

## Edge Cases

- <<TEMP>>
- 입력된 이름이 비어있는 경우
- 입력된 이름이 시스템에서 예약한 문자열인 경우
- 인젝션

## Acceptance Criteria

- [ ] <<AI>> 이름을 변경할 Content Tab이 선택된 상태에서 사용자가 해당 인터랙션을 호출하고 유효한 새
      이름을 입력해 확정하면, 해당 Content Tab 라벨이 새 이름으로 변경되고 이후 세션에서도 동일하게
      표시됨.
- [ ] <<AI>> 새 이름 입력 없이 비어 있는 값으로 확정하려 할 때 사용자가 해당 인터랙션을 호출하면,
      기존 이름을 유지하거나 유효하지 않은 이름에 대한 경고를 표시함.
- [ ] <<AI>> 시스템 예약 문자열 등 허용되지 않은 이름으로 변경을 시도한 상태에서 사용자가 해당
      인터랙션을 호출하면, 이름이 변경되지 않고 이유를 안내하는 피드백을 표시함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `216`
