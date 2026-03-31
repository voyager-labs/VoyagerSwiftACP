# Apply Generated Filter Changes

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-001-apply_generated_filter_changes |
| Interaction Type | background |
| Feature | Define Collection Filter |
| Category Key | RCL |
| Feature ID | RCL-001 |
| Status | 배포 완료 |
| Summary | 생성된 필터 변경안을 현재 필터 정의에 일괄 반영 |
| Related Region | file_manager_window.content_pane.content_header.collection_filter_composer |
| Menu | - |
| Shortcut | - |

## Preconditions

- Generate Filter Changes from Query 결과가 성공으로 반환된 상태
## Edge Cases

- -

## Acceptance Criteria

- [ ] Generate 결과가 성공으로 반환된 상태일 때, 시스템이 변경안을 적용하면, 현재 필터 정의가 최신 생성본으로 갱신됨

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `106`
