# Group Entries by Property

## Metadata

| Field            | Value                                                                                                                          |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Interaction ID   | EVM-002-group_entries_by_property                                                                                              |
| Interaction Type | command                                                                                                                        |
| Feature          | Configure Entries View                                                                                                         |
| Category Key     | EVM                                                                                                                            |
| Feature ID       | EVM-002                                                                                                                        |
| Status           | 배포 완료                                                                                                                      |
| Summary          | Entries View에서 선택한 Property를 기준으로 Entries를 그룹 섹션으로 묶어 같은 속성의 Entry 하나의 그룹 헤더 아래에 모아서 표시 |
| Related Region   | file_manager_window.content_pane                                                                                               |
| Menu             | View                                                                                                                           |
| Shortcut         | -                                                                                                                              |

## Preconditions

- Entries View가 Icon View로 설정된 상태

## Edge Cases

- 선택한 프로퍼티 값이 일부 Entry에는 존재하지 않는 경우

## Acceptance Criteria

- [ ] 현재 Entries View가 Icon View일 때, 해당 인터랙션을 호출하면, 선택한 프로퍼티를 기준으로
      엔트리가 그룹 섹션으로 묶여 표시됨
- [ ] 특정 프로퍼티 그룹 섹션으로 묶여 표시될 때, 해당 프로퍼티가 없는 엔트리가 존재한다면, “미지정”
      그룹에 표시됨

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `27`
