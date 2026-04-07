# Discard Collection Filter Changes

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-002-discard_collection_filter_changes |
| Interaction Type | command |
| Feature | Manage Retrieval Collections |
| Category Key | RCL |
| Feature ID | RCL-002 |
| Status | 배포 완료 |
| Summary | 미저장 필터 변경 사항을 폐기하고 마지막 저장본의 필터 정의로 되돌림 |
| Related Region | file_manager_window.content_pane.content_header.collection_filter_composer |
| Menu | File |
| Shortcut | - |

## Preconditions

- 마지막 저장 상태 기준점이 존재하는 상태
- 현재 필터 구성이 기준점과 다른 상태
- 미저장 필터 변경이 존재하는 상태
## Edge Cases

- -

## Acceptance Criteria

- [ ] 저장된 콜렉션 파일을 불러와 미저장 필터 변경이 존재할 때, 사용자가 해당 인터랙션을 호출하면, 현재 필터 구성을 마지막 저장본의 필터 정의로 복원함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `125`
