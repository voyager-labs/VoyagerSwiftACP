# ONB Onboarding Session Flow

## Intent

`ONB-001`은 앱 첫 실행 또는 온보딩 재진입 시 Welcome, Beta Access, Permissions, Complete 단계를 순서대로 진행하고, progress snapshot을 저장·복원해 사용자가 필요한 준비 상태에 도달하도록 하는 흐름을 정의한다.

## Contract References

- 이 흐름은 onboarding session, progress snapshot, step completion state를 다루며 별도 category contract 없이 `onboarding_window` IA region을 기준으로 정렬한다.

## Interaction Coverage

- [ONB-001-start_onboarding_session](../ONB-001-run_user_onboarding/ONB-001-start_onboarding_session.md)
- [ONB-001-show_onboarding_step](../ONB-001-run_user_onboarding/ONB-001-show_onboarding_step.md)
- [ONB-001-update_onboarding_step_state](../ONB-001-run_user_onboarding/ONB-001-update_onboarding_step_state.md)
- [ONB-001-advance_onboarding_step](../ONB-001-run_user_onboarding/ONB-001-advance_onboarding_step.md)
- [ONB-001-go_back_onboarding_step](../ONB-001-run_user_onboarding/ONB-001-go_back_onboarding_step.md)
- [ONB-001-resume_onboarding_session](../ONB-001-run_user_onboarding/ONB-001-resume_onboarding_session.md)
- [ONB-001-complete_onboarding_session](../ONB-001-run_user_onboarding/ONB-001-complete_onboarding_session.md)

## Flow Overview

```mermaid
flowchart LR
  A[Start session] --> B[Welcome]
  B --> C[Beta Access]
  C --> D[Permissions]
  D --> E[Complete]
  E --> F[Open main window and close onboarding]
```

## Happy Path

1. Onboarding window가 나타나면 progress snapshot을 로드한다.
2. snapshot이 없으면 새 session을 만들고 Welcome부터 시작한다.
3. 각 step의 child action이 발생할 때마다 current step과 completion state를 snapshot으로 저장한다.
4. Next는 현재 step이 complete일 때만 다음 step으로 이동한다.
5. Complete step에서 Start Using이 성공하면 default tab path로 main window를 열고 onboarding window를 닫는다.

## Alternate Paths

### Resume Existing Session

1. snapshot이 있으면 저장된 step completion state를 복원한다.
2. 저장된 currentStep이 아직 complete가 아니면 마지막 유효 step으로 되돌려 재개한다.

### Permissions Recovery

1. Full Disk Access 또는 Helper folder access가 granted가 아니면 Permissions step은 complete가 아니다.
2. 시스템 설정 열기 실패나 folder access 요청 실패는 retry 가능한 오류로 표시한다.

### Complete Failure

1. main window open이 실패하면 onboarding window를 닫지 않는다.
2. 사용자는 Complete step에서 retry할 수 있다.

## Boundary Notes

- Beta Access 검증 자체는 BetaAccess feature가 소유하고, ONB는 completion state와 step transition만 소유한다.
- Full Disk Access와 Helper folder access 확인은 Permissions step의 dependency 경계에서 수행한다.
- Complete 이후 파일 관리자 창의 실제 탐색 state는 File Manager feature가 소유한다.

## Source

- Category: `ONB`
- Covered feature: `ONB-001 Run User Onboarding`
