# Open Collection Filter Composer

## Metadata

| Field            | Value                                                                                                     |
| ---------------- | --------------------------------------------------------------------------------------------------------- |
| Interaction ID   | RCL-001-open_collection_filter_composer                                                                   |
| Interaction Type | command                                                                                                   |
| Feature          | Define Collection Filter                                                                                  |
| Category Key     | RCL                                                                                                       |
| Feature ID       | RCL-001                                                                                                   |
| Status           | 배포 완료                                                                                                 |
| Summary          | Entries View 상단에서 Collection Filter Composer를 열어 현재 콜렉션의 스코프·조건을 편집 가능 상태로 전환 |
| Related Region   | file_manager_window.content_pane.content_header.collection_filter_composer                                |
| Menu             | Edit                                                                                                      |
| Shortcut         | ⌘F                                                                                                        |

## Preconditions

- 현재 페이지가 필터 편집을 지원하는 상태

## Edge Cases

- 이미 Collection Filter Composer가 열린 상태에서 호출되는 경우
- 미저장 필터 변경이 존재하는 경우

## Acceptance Criteria

- [ ] 현재 페이지가 필터 편집을 지원하는 상태일 때, 사용자가 해당 인터랙션을 호출하면, Collection
      Filter Composer가 표시되고 Filter Query 입력 필드로 포커스가 이동함
- [ ] Composer가 이미 열린 상태일 때, 사용자가 해당 인터랙션을 호출하면, Filter Query 입력 필드로
      포커스가 이동함
- [ ] 미저장 필터 변경이 존재하는 상태일 때, 사용자가 해당 인터랙션을 호출하면, 미저장 변경이 반영된
      Composer를 표시함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `101`
