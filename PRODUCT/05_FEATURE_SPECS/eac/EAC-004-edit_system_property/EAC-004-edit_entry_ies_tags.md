# Edit Entry(ies) Tags

## Metadata

| Field            | Value                                                               |
| ---------------- | ------------------------------------------------------------------- |
| Interaction ID   | EAC-004-edit_entry_ies_tags                                         |
| Interaction Type | command                                                             |
| Feature          | Edit System Property                                                |
| Category Key     | EAC                                                                 |
| Feature ID       | EAC-004                                                             |
| Status           | 기획 완료                                                           |
| Summary          | 선택한 Entry의 태그(라벨/색)를 추가·제거·변경                       |
| Related Region   | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu             | File                                                                |
| Shortcut         | -                                                                   |

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태
- <<AI>> 선택된 Entry의 태그 메타데이터를 편집할 수 있는 상태

## Edge Cases

- <<AI>> 일부 Entry가 태그 쓰기를 지원하지 않는 스토리지에 있는 경우
- <<AI>> 권한 문제로 태그 쓰기가 불가능한 경우
- <<AI>> 다중 선택에서 서로 다른 기존 태그 조합으로 표시가 복잡한 경우

## Acceptance Criteria

- [ ] <<AI>> 하나 이상의 Entry가 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 태그를
      추가·제거·변경할 수 있는 UI를 표시함.
- [ ] <<AI>> 태그 변경이 확정된 상태일 때, 시스템이 적용하면, 태그 메타데이터를 갱신하고 UI 표시를
      반영함.
- [ ] <<AI>> 일부 Entry에 적용 불가한 상태일 때, 시스템이 적용하면, 적용 가능한 Entry만 반영하고
      실패 대상과 사유를 사용자에게 안내함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `59`
