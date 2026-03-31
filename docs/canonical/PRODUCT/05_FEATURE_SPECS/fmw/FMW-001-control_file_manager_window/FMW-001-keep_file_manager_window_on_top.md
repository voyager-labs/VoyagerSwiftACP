# Keep File Manager Window on Top

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | FMW-001-keep_file_manager_window_on_top |
| Interaction Type | command |
| Feature | Control File Manager Window |
| Category Key | FMW |
| Feature ID | FMW-001 |
| Status | 준비 완료 |
| Summary | File Manager 창을 다른 앱보다 항상 위로 고정 |
| Related Region | file_manager_window |
| Menu | Window |
| Shortcut | - |

## Preconditions

- -
## Edge Cases

- -

## Acceptance Criteria

- [ ] 대상 File Manager Window가 일반 창 상태일 때, 사용자가 해당 인터랙션을 호출하면, 해당 창이 “항상 위” 상태로 전환되어 다른 일반 창보다 위에 유지됨
- [ ] 대상 File Manager Window이 이미 "항상 위" 상태 일 떄, 사용자가 해당 인터랙션을 다시 호출하면, 해당 창은 일반 창 상태로 전환됨

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `8`
