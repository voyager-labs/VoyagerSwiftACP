# Delete Indexing Exclusion Rule

## Metadata

| Field            | Value                                               |
| ---------------- | --------------------------------------------------- |
| Interaction ID   | EIX-003-delete_indexing_exclusion_rule              |
| Interaction Type | command                                             |
| Feature          | Configure Indexed Entries                           |
| Category Key     | EIX                                                 |
| Feature ID       | EIX-003                                             |
| Status           | 준비 완료                                           |
| Summary          | 선택한 인덱싱 제외 규칙을 삭제해 규칙 목록에서 제거 |
| Related Region   | settings_window.settings_body.tab_indexing          |
| Menu             | -                                                   |
| Shortcut         | -                                                   |

## Preconditions

- <<TEMP>>
- 삭제할 제외 규칙이 선택된 상태

## Edge Cases

-   -

## Acceptance Criteria

- [ ] 삭제할 제외 규칙이 선택된 상태일 때, 사용자가 삭제를 확정하면, 시스템이 해당 규칙을 삭제하고
      규칙 목록에 반영함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `82`
