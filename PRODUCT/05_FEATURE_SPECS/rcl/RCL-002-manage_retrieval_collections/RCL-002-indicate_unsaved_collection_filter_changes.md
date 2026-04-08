# Indicate Unsaved Collection Filter Changes

## Metadata

| Field            | Value                                                           |
| ---------------- | --------------------------------------------------------------- |
| Interaction ID   | RCL-002-indicate_unsaved_collection_filter_changes              |
| Interaction Type | display                                                         |
| Feature          | Manage Retrieval Collections                                    |
| Category Key     | RCL                                                             |
| Feature ID       | RCL-002                                                         |
| Status           | 배포 완료                                                       |
| Summary          | 저장되지 않은 필터 변경 상태를 알리는 표시를 타이틀 바에 나타냄 |
| Related Region   | file_manager_window.content_pane.content_header.page_info_area  |
| Menu             | -                                                               |
| Shortcut         | -                                                               |

## Preconditions

- 마지막 저장 상태 기준점이 존재하는 상태
- 현재 필터 구성이 기준점과 다른 상태

## Edge Cases

-   -

## Acceptance Criteria

- [ ] 저장된 콜렉션 파일을 불러와 보고 있을 때, 현재 필터 구성이 마지막 저장 기준점과 다른 상태라면,
      타이틀 바에 미저장 인디케이터가 표시됨

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `124`
