# Delete Collection Condition

## Metadata

| Field            | Value                                                                      |
| ---------------- | -------------------------------------------------------------------------- |
| Interaction ID   | RCL-001-delete_collection_condition                                        |
| Interaction Type | command                                                                    |
| Feature          | Define Collection Filter                                                   |
| Category Key     | RCL                                                                        |
| Feature ID       | RCL-001                                                                    |
| Status           | 배포 완료                                                                  |
| Summary          | 선택한 컨디션을 필터에서 제거                                              |
| Related Region   | file_manager_window.content_pane.content_header.collection_filter_composer |
| Menu             | -                                                                          |
| Shortcut         | ⌫                                                                          |

## Preconditions

- Generate Filter Changes from Query가 실행 중이지 않은 상태
- 삭제 대상 컨디션이 존재하는 상태
- 삭제 대상 컨디션이 지정된 상태

## Edge Cases

- 마지막 남은 컨디션을 제거하는 경우

## Acceptance Criteria

- [ ] Collection Filter Composer가 열린 상태일 때, 사용자가 해당 인터랙션을 호출하면, 해당 컨디션이
      필터에서 제거됨
- [ ] 사용자가 컨디션을 제거하려할 때, 해당 컨디션이 마지막 남은 컨디션이라면, 콜렉션은 컨디션 없는
      상태가 됨

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `120`
