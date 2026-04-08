# Reorder Selected Content Tabs

## Metadata

| Field            | Value                                                      |
| ---------------- | ---------------------------------------------------------- |
| Interaction ID   | CTM-001-reorder_selected_content_tabs                      |
| Interaction Type | command                                                    |
| Feature          | Handle Content Tab                                         |
| Category Key     | CTM                                                        |
| Feature ID       | CTM-001                                                    |
| Status           | 준비 완료                                                  |
| Summary          | 선택한 Content Tab들의 순서를 재배치                       |
| Related Region   | file_manager_window.sidebar.sidebar_body.content_tabs_area |
| Menu             | -                                                          |
| Shortcut         | -                                                          |

## Preconditions

- 2개 이상의 Content Tab이 열린 상태
- 1개 이상의 Content Tab이 지정된 상태

## Edge Cases

- 재배치 중인 Content Tab을 다른 창으로 이동시키는 경우

## Acceptance Criteria

- [ ] <<AI>> 둘 이상의 Content Tab이 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 선택된 탭
      그룹이 드래그 종료 위치 기준으로 연속된 블록으로 재배치됨.
- [ ] <<AI>> 드래그 도중 일부 탭이 닫히거나 이동된 경우, 사용자가 인터랙션을 마무리하면, 실제 남아
      있는 탭들만을 대상으로 순서가 일관되게 갱신됨.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `203`
