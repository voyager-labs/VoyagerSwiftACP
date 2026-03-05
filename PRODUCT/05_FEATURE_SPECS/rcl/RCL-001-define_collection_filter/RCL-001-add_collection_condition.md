# Add Collection Condition

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-001-add_collection_condition |
| Interaction Type | command |
| Feature | Define Collection Filter |
| Category Key | RCL |
| Feature ID | RCL-001 |
| Status | 배포 완료 |
| Summary | Collection Filter Composer에 새 컨디션을 수동으로 추가 |
| Related Region | file_manager_window.content_pane.content_header.collection_fillter_composer |
| Menu | - |
| Shortcut | - |

## Preconditions

- Collection Filter Composer가 열린 상태
- Generate Filter Changes from Query가 실행 중이지 않은 상태
## Edge Cases

- 미완성 컨디션이 이미 존재하는 경우

## Acceptance Criteria

- [ ] Collection Filter Composer가 열린 상태일 때, 사용자가 해당 인터랙션을 호출하면, 새 컨디션이 필터 영역에 추가되고 해당 컨디션이 포커스되어 프로퍼티 편집 상태가 됨
- [ ] 새 컨디션을 추가했을 때, 프로퍼티∙오퍼레이터∙밸류를 완성하지 않은 미완성 상태로 편집을 종료한다면, 해당 컨디션의 미완성 상태로 표시하고 조건에서 제외함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `116`
