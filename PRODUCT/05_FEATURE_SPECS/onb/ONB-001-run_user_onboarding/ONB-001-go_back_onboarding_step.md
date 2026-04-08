# Go Back Onboarding Step

## Metadata

| Field            | Value                                 |
| ---------------- | ------------------------------------- |
| Interaction ID   | ONB-001-go_back_onboarding_step       |
| Interaction Type | input                                 |
| Feature          | Run User Onboarding                   |
| Category Key     | ONB                                   |
| Feature ID       | ONB-001                               |
| Status           | 배포 완료                             |
| Summary          | 이전 스텝으로 이동하고, 입력값을 복원 |
| Related Region   | onboarding_window                     |
| Menu             | -                                     |
| Shortcut         | -                                     |

## Preconditions

- 이전 스텝이 존재하는 상태

## Edge Cases

-   -

## Acceptance Criteria

- [ ] 이전 스텝이 존재하는 상태일 때, 해당 인터랙션을 호출하면, 이전 온보딩 스텝으로 이동함
- [ ] 이전 스텝으로 이동했을 때, 입력 상태가 존재한다면, 해당 값을 복구함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `243`
