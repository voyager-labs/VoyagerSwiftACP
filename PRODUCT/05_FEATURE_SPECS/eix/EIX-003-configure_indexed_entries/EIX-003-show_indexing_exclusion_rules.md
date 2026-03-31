# Show Indexing Exclusion Rules

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EIX-003-show_indexing_exclusion_rules |
| Interaction Type | display |
| Feature | Configure Indexed Entries |
| Category Key | EIX |
| Feature ID | EIX-003 |
| Status | 준비 완료 |
| Summary | gitignore와 같은 정규표현식 규칙 기반으로 인덱싱에서 제외되는 경로·패턴 규칙을 표시 |
| Related Region | settings_window.settings_body.tab_indexing |
| Menu | - |
| Shortcut | - |

## Preconditions

- <<TEMP>>
- 인덱싱 설정 화면이 표시된 상태
## Edge Cases

- 제외 목록이 비어 있는 경우

## Acceptance Criteria

- [ ] 인덱싱 설정 화면이 표시된 상태일 때, 시스템이 제외 규칙을 로드하면, gitignore와 같은 정규표현식 규칙 기반 제외 규칙 목록을 표시함
- [ ] 제외 목록이 비어 있는 경우일 때, 시스템이 규칙 목록을 표시하면, 빈 상태를 표시함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `79`
