# Complete Onboarding Session

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | ONB-001-complete_onboarding_session |
| Interaction Type | background |
| Feature | Run User Onboarding |
| Category Key | ONB |
| Feature ID | ONB-001 |
| Status | 배포 완료 |
| Summary | 온보딩을 완료 처리하고 파일 관리자 창을 실행 |
| Related Region | onboarding_window |
| Menu | - |
| Shortcut | - |

## Preconditions

- 온보딩의 최종 단계에 도달한 상태
- 마지막 스텝 완료 조건을 충족한 상태.
## Edge Cases

- 완료 플래그 저장 실패로 다음 실행에서 온보딩이 다시 시작되는 경우
- 완료 후에도 온보딩 화면에서 벗어나지 못하는 경우

## Acceptance Criteria

- [ ] 온보딩의 마지막 스텝에 도달한 상태일 때, 해당 인터랙션을 호출하면, 완료 플래그 저장 후 파일 관리자 창을 실행함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `245`
