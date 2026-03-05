# Update Indexing Exclusion Rule

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EIX-003-update_indexing_exclusion_rule |
| Interaction Type | command |
| Feature | Configure Indexed Entries |
| Category Key | EIX |
| Feature ID | EIX-003 |
| Status | 준비 완료 |
| Summary | 기존 인덱싱 제외 규칙을 수정해 규칙 목록에 반영 |
| Related Region | settings_window.settings_body.tab_indexing |
| Menu | - |
| Shortcut | - |

## Preconditions

- <<TEMP>>
- 제외 규칙 편집 화면이 표시된 상태
- 수정할 제외 규칙이 선택된 상태
## Edge Cases

- 입력한 경로·패턴이 유효하지 않아 규칙을 저장할 수 없는 경우
- 수정 결과가 기존 규칙과 중복되는 경우

## Acceptance Criteria

- [ ] 수정할 제외 규칙이 선택된 상태일 때, 사용자가 규칙 수정을 저장하면, 시스템이 해당 규칙을 갱신하고 규칙 목록에 반영함
- [ ] 입력한 경로·패턴이 유효하지 않은 경우일 때, 사용자가 저장하면, 시스템이 저장을 차단하고 유효하지 않은 입력을 표시함
- [ ] 수정 결과가 기존 규칙과 중복되는 경우일 때, 사용자가 저장하면, 시스템이 저장을 차단하거나 충돌을 해소하도록 안내함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `81`
