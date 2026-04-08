# Sort Entrires by Property

## Metadata

| Field            | Value                                                                  |
| ---------------- | ---------------------------------------------------------------------- |
| Interaction ID   | EVM-002-sort_entrires_by_property                                      |
| Interaction Type | command                                                                |
| Feature          | Configure Entries View                                                 |
| Category Key     | EVM                                                                    |
| Feature ID       | EVM-002                                                                |
| Status           | 배포 완료                                                              |
| Summary          | Entries View에서 선택한 Property를 기준으로 Entries 표시 순서를 정렬함 |
| Related Region   | file_manager_window.content_pane                                       |
| Menu             | View                                                                   |
| Shortcut         | -                                                                      |

## Preconditions

- Entries View가 List / Icon / Column VIew로 설정된 상태
- 정렬 가능한 프로퍼티가 정의된 상태

## Edge Cases

-   -

## Acceptance Criteria

- [ ] 현재 페이지가 Entries를 정상적으로 표시하고 있을 때, 사용자가 해당 인터랙션을 호출하면, 선택한
      프로퍼티 기준으로 Entries가 오름/내림차순으로 재정렬됨
- [ ] 선택한 프로퍼티로 정렬을 유지할 때, 엔트리 간 동일 값이 존재한다면, 기본적으로 이름을 2차 정렬
      규칙으로 적용함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `28`
