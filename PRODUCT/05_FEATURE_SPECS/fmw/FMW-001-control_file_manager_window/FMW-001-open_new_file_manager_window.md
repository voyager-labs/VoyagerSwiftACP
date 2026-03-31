# Open New File Manager Window

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | FMW-001-open_new_file_manager_window |
| Interaction Type | command |
| Feature | Control File Manager Window |
| Category Key | FMW |
| Feature ID | FMW-001 |
| Status | 배포 완료 |
| Summary | 현재 사용 중인 데스크탑에서 새 File Manager 창을 생성해 새로운 세션을 시작 |
| Related Region | file_manager_window |
| Menu | File |
| Shortcut | ⌘N |

## Preconditions

- 앱 활성 상태
## Edge Cases

- 사용 가능한 메모리가 부족한 상태에서 호출되는 경우

## Acceptance Criteria

- [ ] 앱이 활성 상태일 때, 사용자가 해당 인터랙션을 호출하면, 현재 데스크탑에 새 File Manager Window가 하나 생성되고 활성 창으로 전환됨
- [ ] 시스템 메모리 또는 리소스 부족으로 새 창을 생성할 수 없는 상태일 때, 사용자가 해당 인터랙션을 호출하면, 새 창이 생성되지 않음

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `3`
