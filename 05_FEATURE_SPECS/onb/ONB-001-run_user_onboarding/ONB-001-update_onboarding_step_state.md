# Update Onboarding Step State

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | ONB-001-update_onboarding_step_state |
| Interaction Type | background |
| Feature | Run User Onboarding |
| Category Key | ONB |
| Feature ID | ONB-001 |
| Status | 배포 완료 |
| Summary | 사용자가 스텝 내 입력을 변경하면 진행 상태에 반영하고, 상태를 저장해 재개 가능 상태를 유지 |
| Related Region | onboarding_window |
| Menu | - |
| Shortcut | - |

## Preconditions

- 온보딩 스텝이 표시된 상태
## Edge Cases

- 입력 저장 직전에 세션이 종료되는 경우

## Acceptance Criteria

- [ ] 온보딩 스텝이 표시된 상태일 때, 입력 변경이 발생하면, 변경 내용이 진행 상태에 반영되고 저장됨
- [ ] 입력 저장 직전에 세션이 종료될 때, 세션이 종료되면, 저장 완료된 마지막 진행 상태가 유지됨

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `241`
