# Change Collection Condition Property

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-001-change_collection_condition_property |
| Interaction Type | input |
| Feature | Define Collection Filter |
| Category Key | RCL |
| Feature ID | RCL-001 |
| Status | 배포 완료 |
| Summary | 선택한 컨디션의 기준 프로퍼티를 다른 프로퍼티로 변경 |
| Related Region | file_manager_window.content_pane.content_header.collection_filter_composer |
| Menu | - |
| Shortcut | - |

## Preconditions

- Generate Filter Changes from Query가 실행 중이지 않은 상태
- 편집 대상 컨디션이 존재하는 상태
- 편집 대상 컨디션이 지정된 상태
## Edge Cases

- 프로퍼티 변경으로 기존 오퍼레이터·값 구성이 무효가 되는 경우

## Acceptance Criteria

- [ ] 해당 컨디션이 프로퍼티 편집 상태일 때, 사용자가 해당 인터랙션을 호출하면, 해당 컨디션의 기준 프로퍼티가 갱신됨
- [ ] 사용자가 기준 프로퍼티를 변경했을 때, 기존 오퍼레이터·값 구성이 무효가 된다면, 오퍼레이터는 기본값으로 설정되며, 값은 초기화됨

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `117`
