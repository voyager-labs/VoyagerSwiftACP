# Remove Directory From Collection Scope

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-001-remove_directory_from_collection_scope |
| Interaction Type | command |
| Feature | Define Collection Filter |
| Category Key | RCL |
| Feature ID | RCL-001 |
| Status | 배포 완료 |
| Summary | 스코프 메뉴에서 디렉토리를 제거해 콜렉션 스코프를 축소 |
| Related Region | file_manager_window.content_pane.content_header.collection_filter_composer |
| Menu | - |
| Shortcut | - |

## Preconditions

- Collection Filter Composer가 열린 상태
- 스코프 메뉴가 열린 상태
- Generate Filter Changes from Query가 실행 중이지 않은 상태
## Edge Cases

- 마지막 남은 디렉토리를 제거하는 경우
- 현재 디렉토리를 제거하는 경우

## Acceptance Criteria

- [ ] 스코프 메뉴에서 특정 스코프된 디렉토리에 포커스했을 때, 사용자가 해당 인터랙션을 호출하면, 해당 디렉토리가 스코프에서 제외됨
- [ ] 사용자가 스코프 집합에서 특정 디렉토리에서 제외하려할 때, 마지막 디렉토리가 제거된다면, 현재 스코프를 전체 스토리지 스코프 상태로 전환함
- [ ] 현재 페이지가 디렉토리 페이지일 때, 사용자가 스코프 집합에서 현재 디렉토리를 제외하려한다면, 남은 스코프 집합을 따르거나 전체 스토리지 스코프 상태로 전환됨

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `115`
