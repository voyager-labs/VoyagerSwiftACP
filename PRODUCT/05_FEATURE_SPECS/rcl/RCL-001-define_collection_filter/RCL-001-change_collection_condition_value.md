# Change Collection Condition Value

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-001-change_collection_condition_value |
| Interaction Type | input |
| Feature | Define Collection Filter |
| Category Key | RCL |
| Feature ID | RCL-001 |
| Status | 배포 완료 |
| Summary | 선택한 컨디션의 비교 값 또는 범위를 편집해 해당 조건이 만족하는 엔트리 집합을 조정 |
| Related Region | file_manager_window.content_pane.content_header.collection_filter_composer |
| Menu | - |
| Shortcut | - |

## Preconditions

- Generate Filter Changes from Query가 실행 중이지 않은 상태
- 편집 대상 컨디션이 존재하는 상태
- 해당 컨디션의 프로퍼티와 오퍼레이터가 설정된 상태
## Edge Cases

- 범위 입력이 필요한데 한쪽 값만 확정되는 경우

## Acceptance Criteria

- [ ] 해당 컨디션이 값 편집 상태일 때, 사용자가 해당 인터랙션을 호출하면, 해당 컨디션의 값이 갱신됨
- [ ] 설정된 오퍼레이터에 따라 범위 입력이 필요할 때, 한쪽 값만 입력이 되었다면, 해당 컨디션은 미완성 상태로 표시됨

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `119`
