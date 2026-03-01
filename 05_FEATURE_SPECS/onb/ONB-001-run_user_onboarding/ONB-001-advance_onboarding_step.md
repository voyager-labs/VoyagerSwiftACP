# Advance Onboarding Step

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | ONB-001-advance_onboarding_step |
| Interaction Type | input |
| Feature | Run User Onboarding |
| Category Key | ONB |
| Feature ID | ONB-001 |
| Status | 배포 완료 |
| Summary | 현재 스텝의 완료 조건(FDA, Launch at Login 등)을 검증하고, 다음 스텝으로 이동 |
| Related Region | onboarding_window |
| Menu | - |
| Shortcut | - |

## Preconditions

- 온보딩 스텝이 표시된 상태
- 현재 스텝에서 다음 단계 이동 경로가 존재하는 상태
- 현재 스텝의 완료 조건이 충족된 상태
## Edge Cases

- -

## Acceptance Criteria

- [ ] 현재 스텝의 완료 조건이 통과된 상태일 때, 해당 인터랙션을 호출하면, 다음 온보딩 스텝으로 이동함
- [ ] 모든 입력을 완료했을 떄, 완료 조건이 미충족인 상태라면, 해당 인터랙션이 비활성화됨

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `242`
