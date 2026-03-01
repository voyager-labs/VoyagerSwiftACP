# Submit Collection Filter Query

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-001-submit_collection_filter_query |
| Interaction Type | command |
| Feature | Define Collection Filter |
| Category Key | RCL |
| Feature ID | RCL-001 |
| Status | 배포 완료 |
| Summary | 텍스트필드에 입력된 쿼리를 제출해 필터 생성 파이프라인을 시작 |
| Related Region | file_manager_window.content_pane.content_header.collection_fillter_composer |
| Menu | - |
| Shortcut | ⏎ |

## Preconditions

- Collection Filter Composer가 열린 상태
- Filter Query 입력 필드가 포커스된 상태
- 입력값이 존재하는 상태
- Generate Filter Changes from Query가 실행 중이지 않은 상태
## Edge Cases

- 직전과 동일 입력값을 연속 제출하는 경우

## Acceptance Criteria

- [ ] 텍스트필드에 값이 존재하는 상태일 때, 사용자가 해당 인터랙션을 호출하면, Generate Filter Suggestions from Query가 시작됨
- [ ] Generate Filter Suggestions from Query가 실행 중일 때, 사용자가 텍스트필드에 값을 입력했더라도, 사용자가 해당 인터랙션을 호출을 진행할 수 없음
- [ ] 사용자가 해당 인터랙션이 호출되었을 때, 직전과 동일 입력값을 연속 제출했다면, 시스템이 중복 실행을 시작하지 않고 기존 실행 또는 직전 결과를 유지함

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `104`
