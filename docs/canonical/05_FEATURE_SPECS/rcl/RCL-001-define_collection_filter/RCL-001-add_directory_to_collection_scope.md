# Add Directory To Collection Scope

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-001-add_directory_to_collection_scope |
| Interaction Type | command |
| Feature | Define Collection Filter |
| Category Key | RCL |
| Feature ID | RCL-001 |
| Status | 배포 완료 |
| Summary | 스코프 메뉴에서 디렉토리를 추가해 콜렉션 스코프를 디렉토리 집합으로 확장 |
| Related Region | file_manager_window.content_pane.content_header.collection_fillter_composer |
| Menu | - |
| Shortcut | - |

## Preconditions

- Collection Filter Composer가 열린 상태
- 스코프 메뉴가 열린 상태
- Generate Filter Changes from Query가 실행 중이지 않은 상태
## Edge Cases

- 상위/하위 관계의 디렉토리를 추가하는 경우
- 추가하려는 디렉토리가 이미 스코프에 포함된 경우
- 전체 스토리지 스코프 상태에서 디렉토리를 추가하는 경우

## Acceptance Criteria

- [ ] 스코프 메뉴에서 특정 디렉토리에 포커스했을 때, 사용자가 해당 인터랙션을 호출하면, 해당 디렉토리가 스코프에 포함됨
- [ ] 사용자가 특정 디렉토리를 스코프에 추가하려할 때, 해당 디렉토리가 이미 스코프에 포함되어 있다면, 중복으로 판단해 스코프에 추가하지 않음
- [ ] 상위 디렉토리가 스코프에 포함된 상태일 때, 사용자가 하위 디렉토리를 추가하면, 상위 디렉토리를 제거하고 하위 디렉토리로 교체함
- [ ] 하위 디렉토리가 스코프에 포함된 상태일 때, 사용자가 상위 디렉토리를 추가하면, 하위 디렉토리를 제거하고 상위 디렉토리로 교체함
- [ ] 현재 전체 스토리지 스코프 상태일 때, 사용자가 특정 디렉토리를 추가하려 한다면, 현재 스코프를 디렉토리 집합 상태로 전환함

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `114`
