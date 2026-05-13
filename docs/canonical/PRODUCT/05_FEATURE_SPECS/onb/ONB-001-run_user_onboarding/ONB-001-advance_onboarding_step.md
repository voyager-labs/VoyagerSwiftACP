---
interaction_id: "ONB-001-advance_onboarding_step"
interaction_type: "input"
feature: "Run User Onboarding"
category_key: "ONB"
feature_id: "ONB-001"
status: "배포 완료"
summary: "현재 스텝의 완료 조건(FDA, Launch at Login 등)을 검증하고, 다음 스텝으로 이동"
related_region: "onboarding_window"
menu: "-"
shortcut: "-"
---

# Advance Onboarding Step

## Intent

- 현재 스텝의 완료 조건(FDA, Launch at Login 등)을 검증하고, 다음 스텝으로 이동.
- `ONB-001`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- Onboarding window가 표시되거나 사용자가 Next/Back/Start Using 계열 action을 실행할 때 호출된다.
- Welcome, Beta Access, Permissions, Complete child step에서 상태 변경이 발생할 때 호출된다.

## Preconditions

- Onboarding state와 progress snapshot store를 읽고 쓸 수 있어야 한다.
- 온보딩 단계는 Welcome, Beta Access, Permissions, Complete 순서를 따른다.

## Expected Outcome

- 현재 스텝의 완료 조건(FDA, Launch at Login 등)을 검증하고, 다음 스텝으로 이동.
- 온보딩 단계는 Welcome, Beta Access, Permissions, Complete 순서로 표시되어야 한다.
- progress snapshot은 currentStep과 각 step completion 상태를 저장해 재실행 시 복원 가능해야 한다.
- Next는 현재 step이 complete일 때만 다음 step으로 이동해야 한다.

## State Changes

- currentStep, welcome/betaAccess/permissions/complete completion state, progress snapshot을 갱신한다.
- 저장된 snapshot이 유효하지 않으면 마지막 유효 step 또는 Welcome으로 되돌린다.
- Complete step에서 main window open 성공 시 onboarding window를 닫는다.

## User-visible Feedback

- 현재 step의 제목, 설명, 입력 UI, progress indicator, Back/Next/Start Using 상태를 표시한다.
- Permissions step은 Full Disk Access와 Helper folder access 상태 및 시스템 설정 진입 오류를 표시한다.
- Complete step의 main window open 실패는 retry 가능한 오류로 표시한다.

## Edge Cases / Failure Handling

- 저장된 snapshot이 resetRequired이면 progress store를 reset하고 새 snapshot을 저장한다.
- 현재 step이 incomplete인데 snapshot currentStep으로 저장되어 있으면 완료된 가장 최근 step으로 복구한다.
- Full Disk Access 설정을 열 수 없으면 수동으로 열라는 오류를 표시한다.
- main window open에 실패하면 onboarding window를 닫지 않는다.
- 입력이 유효하지 않으면 저장/적용을 실행하지 않고 수정 가능한 오류 상태를 유지한다.

## Acceptance Criteria

- [ ] 온보딩을 중간 단계에서 종료하고 다시 열면 마지막 유효 step과 completion state가 복원되어야 한다.
- [ ] 현재 step이 complete가 아니면 Next가 다음 step으로 이동하지 않아야 한다.
- [ ] Permissions에서 Full Disk Access와 Helper folder access가 모두 granted이면 step complete가 되어야 한다.
- [ ] Complete에서 Start Using이 성공하면 main window가 열리고 onboarding window가 닫혀야 한다.

## Permissions / Dependencies

- Onboarding state와 progress snapshot store를 읽고 쓸 수 있어야 한다.
- 온보딩 단계는 Welcome, Beta Access, Permissions, Complete 순서를 따른다.
- 관련 UI region: `onboarding_window`

## Observability / Analytics

- 온보딩 세션 시작/재개/완료
- 현재 step 변경
- 권한 상태 변경
- 메인 윈도우 오픈 실패

## Related Interactions

- [ONB-001-start_onboarding_session](ONB-001-start_onboarding_session.md)
- [ONB-001-show_onboarding_step](ONB-001-show_onboarding_step.md)
- [ONB-001-update_onboarding_step_state](ONB-001-update_onboarding_step_state.md)
- [ONB-001-go_back_onboarding_step](ONB-001-go_back_onboarding_step.md)
- [ONB-001-resume_onboarding_session](ONB-001-resume_onboarding_session.md)
- [ONB-001-complete_onboarding_session](ONB-001-complete_onboarding_session.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:256`
- Flows: [onboarding_session_flow.md](../flows/onboarding_session_flow.md)
- Implementation references: `../voyager-app/docs/features/onboarding.md`, `../voyager-app/apps/macos/Packages/02_Pages/Onboarding/Sources/VoyagerPagesOnboarding/Reducer/OnboardingFeature.swift`, `../voyager-app/apps/macos/Packages/02_Pages/Onboarding/Sources/VoyagerPagesOnboarding/Reducer/PermissionsFeature.swift`, `../voyager-app/apps/macos/Packages/02_Pages/Onboarding/Sources/VoyagerPagesOnboarding/Reducer/CompleteFeature.swift`
