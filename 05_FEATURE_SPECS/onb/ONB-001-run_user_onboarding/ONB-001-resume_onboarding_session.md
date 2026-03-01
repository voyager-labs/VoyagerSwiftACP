# Resume Onboarding Session

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | ONB-001-resume_onboarding_session |
| Interaction Type | background |
| Feature | Run User Onboarding |
| Category Key | ONB |
| Feature ID | ONB-001 |
| Status | 배포 완료 |
| Summary | 미완료 온보딩이 존재할 경우 마지막 유효 스텝에서 재개 |
| Related Region | onboarding_window |
| Menu | - |
| Shortcut | - |

## Preconditions

- 미완료 온보딩 상태가 저장된 상태
## Edge Cases

- 저장된 진행 지점이 현재 온보딩 버전과 불일치하는 경우
- 진행 상태 저장소 접근 실패로 재개를 시작할 수 없는 경우

## Acceptance Criteria

- [ ] 온보딩 세션이 시작되었을 때, 미완료 상태가 있는 상태라면, 마지막 유효 스텝에서 온보딩이 재개됨
- [ ] 온보딩 세션을 재개했을 때, 저장된 진행 지점이 현재 온보딩 버전과 불일치하는 상태라면, 온보딩 단계를 초기화함
- [ ] 온보딩 세션을 재개했을 때, 진행 상태 저장소 접근을 실패한다면, 온보딩 단계를 초기화함

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `244`
