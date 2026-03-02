# Close File Manager Window

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | FMW-001-close_file_manager_window |
| Interaction Type | command |
| Feature | Control File Manager Window |
| Category Key | FMW |
| Feature ID | FMW-001 |
| Status | 배포 완료 |
| Summary | 해당 File Manager 창을 닫음 |
| Related Region | file_manager_window |
| Menu | File |
| Shortcut | ⌘⇧W |

## Preconditions

- 닫을 File Manager Window가 활성 상태
## Edge Cases

- 창에서 진행 중인 작업이 있는 상태의 작업이 있는 경우
- 같은 창에 대해 호출이 중복으로 되는 경우

## Acceptance Criteria

- [ ] 닫을 File Manager Window가 활성 상태일 때, 저장되지 않은 변경사항이 없다면, 대상 창이 즉시 닫히고 관련 리소스가 정리됨
- [ ] 닫을 File Manager Window가 활성 상태일 때,  저장되지 않은 변경 사항이 있다면, 닫기 여부를 묻는 확인 대화를 표시하고 사용자가 닫기를 선택하면 창이 닫히고 관련 리소스가 정리됨
- [ ] File Manager Window가 이미 닫힘 처리 중인 상태일 때, 사용자가 해당 인터랙션을 추가로 호출하면, 중복 종료 동작을 새로 실행하지 않고 기존 종료 흐름만 유지함

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `4`
