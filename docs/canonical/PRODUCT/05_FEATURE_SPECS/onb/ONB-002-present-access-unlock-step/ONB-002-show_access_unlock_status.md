---
interaction_id: "ONB-002-show_access_unlock_status"
interaction_type: "display"
feature: "Present Access Unlock Step"
category_key: "ONB"
feature_id: "ONB-002"
status: "shipped"
phase: "now"
summary: "<<AI>> 온보딩의 접근 권한 검증 스크린에서 계정 로그인 상태와 Core License 기반 앱 잠금 해제 상태, 구매·beta code 입력·접근 상태 새로고침·문의 경로를 표시"
related_region: "onboarding_window.access_unlock_screen"
menu: "-"
shortcut: "-"
---

# Show Access Unlock Status

## Intent

- 사용자가 온보딩 중 이메일과 토큰을 입력받아 beta access 검증 상태를 확인할 수 있도록 `BetaAccessStatus` 기반 접근 권한 화면을 표시한다.
- ONB-002는 gateway 검증 결과로 반환된 `BetaAccessStatus`(active, notActive, checkFailed)를 온보딩 step state로 해석한다.
- [next] 계정 로그인, Core License 구매 검증, beta code 2주 trial, internal test entitlement의 원천 판정을 소유하지 않고 Auth/Entitlement layer가 반환한 `access_status`를 온보딩 step state로 해석한다.
- [next] 사용자가 온보딩 중 계정 로그인 상태와 Voyager 앱 사용 가능 여부를 이해할 수 있도록 `access_status` 기반 앱 잠금 해제 상태와 허용된 회복 경로를 한 화면에서 표시한다.

## Trigger / Entry Points

- ONB-001이 Beta Access step을 현재 step으로 표시할 때 호출된다.
- 사용자가 이메일과 토큰을 입력하고 Check를 실행한 뒤 [ONB-002-apply_access_unlock_result](ONB-002-apply_access_unlock_result.md)가 새 결과를 반영할 때 화면 상태가 다시 계산된다.
- [next] 사용자가 Access Unlock step에서 Retry를 실행하거나 앱이 foreground로 돌아와 `access_status`를 다시 확인할 때 호출된다.

## Preconditions

- 온보딩 세션이 시작되어 있고 current step이 Beta Access이어야 한다.
- 사용자가 이메일과 토큰을 입력할 수 있어야 한다.
- [next] 계정 세션 상태를 확인할 수 있어야 하며, 로그인된 계정이 있을 때 Auth/Entitlement layer에 `access_status` 조회를 요청할 수 있어야 한다.
- [next] `access_status`가 아직 로딩 중이면 화면은 pending 상태로 표시되어야 한다.

## Expected Outcome

- 사용자는 현재 상태가 `active`, `notActive`, `checkFailed` 중 어디에 해당하는지 알 수 있어야 한다.
- `active` 상태에서는 온보딩 진행 가능 상태로 표시된다.
- `notActive` 또는 `checkFailed` 상태에서는 진행 차단 상태로 표시하고 이메일·토큰 재입력을 안내한다.
- Next는 `active` 상태일 때만 enabled 상태가 된다.
- [next] 사용자는 현재 상태가 `complete`, `blocked`, `pending`, `error` 중 어디에 해당하는지 알 수 있어야 한다.
- [next] `core_license_active`, `beta_code_trial_active`, `internal_test_active`는 온보딩 진행 가능 상태로 표시된다.
- [next] 계정이 로그인되어 있지 않거나 `none`, `trial_expired`, `revoked`, `refunded`가 반환되면 진행 차단 상태로 표시하고 로그인, 구매, beta code 입력, 접근 상태 새로고침, 문의, 재시도 중 현재 정책에 허용된 경로를 보여준다.

## State Changes

- display interaction은 gateway 원천 데이터와 온보딩 상태를 변경하지 않는다.
- `BetaAccessStatus` 결과를 읽어 Beta Access step view state와 ONB-001에 전달할 `isComplete` 여부를 계산한다.
- [next] `access_status` 결과를 읽어 Access Unlock step view state와 ONB-001에 전달할 `step_completion_state`를 계산한다.

## User-visible Feedback

- 검증 중에는 접근 권한 확인 중임을 표시하고 Next를 비활성화한다.
- `active` 상태에서는 완료 표시와 다음 단계 진입 가능 상태를 보여준다.
- `notActive` 상태에서는 실패 사유에 해당하는 `BetaAccessReason`을 표시하고 이메일·토큰 재입력을 안내한다.
- `checkFailed` 상태에서는 Retry 가능한 오류로 표시한다.
- [next] 차단 상태에서는 Sign In, Buy Core License, Enter Beta Code, Refresh Access, Contact Support, Retry 중 허용된 액션만 표시한다.
- [next] 네트워크 또는 서버 오류는 `complete`로 취급하지 않고 Retry 가능한 오류로 표시한다.

## Edge Cases / Failure Handling

- 이메일이나 토큰이 누락된 경우 `missingInput` 또는 `missingToken` 사유로 진행을 차단한다.
- 토큰이 유효하지 않으면 `invalidToken` 사유로 진행을 차단한다.
- 이메일이 일치하지 않으면 `emailMismatch` 사유로 진행을 차단한다.
- 기기가 일치하지 않으면 `deviceMismatch` 사유로 진행을 차단한다.
- 네트워크 오류는 `networkError` 사유로 표시하고 Retry를 허용한다.
- gateway 인증 백엔드 오류는 `authBackendError` 사유로 표시한다.
- [next] stale snapshot에 `complete` 상태가 남아 있어도 재진입 시 server-canonical `access_status`가 차단 상태이면 Next를 비활성화한다.
- [next] 회복 경로가 정책상 비활성화된 경우 해당 CTA를 표시하지 않는다.
- [next] `access_status` 응답이 알 수 없는 값이면 진행을 차단하고 Retry와 문의 경로를 표시한다.
- [next] 동일 조회가 중복 실행되면 최신 요청 결과만 화면 상태에 반영한다.

## Acceptance Criteria

- [ ] Beta Access step에 진입한 상황에서 gateway 검증 결과가 `active`이면, 완료 상태와 enabled Next가 표시되어야 한다.
- [ ] 이메일과 토큰을 입력하고 Check를 실행한 상황에서 결과가 `notActive`이면, 실패 사유가 표시되고 Next가 비활성화되어야 한다.
- [ ] gateway 검증이 네트워크 오류로 실패한 상황에서 화면이 표시되면, 실패를 `active`로 처리하지 않고 Retry 가능한 오류를 표시해야 한다.
- [ ] 토큰이 유효하지 않은 경우 `invalidToken` 사유가 사용자에게 표시되어야 한다.
- [ ] 이메일이 일치하지 않는 경우 `emailMismatch` 사유가 사용자에게 표시되어야 한다.
- [ ] [next] Access Unlock step에 진입한 상황에서 `access_status`가 `core_license_active`이면, 완료 상태와 enabled Next가 표시되어야 한다.
- [ ] [next] 로그인된 계정이 없는 상황에서 화면이 표시되면, Next가 비활성화되고 Sign In 경로가 표시되어야 한다.
- [ ] [next] 로그인된 계정의 `access_status`가 `none`인 상황에서 화면이 표시되면, Next가 비활성화되고 현재 허용된 구매, beta code 입력 또는 문의 경로가 표시되어야 한다.
- [ ] [next] 재진입 시 저장된 snapshot과 server-canonical `access_status`가 충돌하면, server-canonical 결과를 기준으로 화면 상태가 갱신되어야 한다.

## Permissions / Dependencies

- Gateway beta access 검증 API 호출이 가능해야 한다.
- 사용자가 이메일과 토큰을 입력할 수 있는 UI가 필요하다.
- [next] Auth account session과 Auth/Entitlement layer의 `access_status` 조회 결과가 필요하다.
- [next] Core License 구매 검증, beta code 2주 trial entitlement, internal test entitlement의 발급과 저장은 ONB-002 밖에서 처리된다.
- ONB-001은 ONB-002가 계산한 `step_completion_state`를 읽어 다음 step 이동 여부를 결정한다.
- 관련 UI region: `onboarding_window.access_unlock_screen`

## Observability / Analytics

- gateway beta access 검증 성공/실패
- [next] `access_status` 조회 성공/실패

## Related Interactions

- [ONB-002-apply_access_unlock_result](ONB-002-apply_access_unlock_result.md)
- [ONB-002-start_access_unlock_recovery](ONB-002-start_access_unlock_recovery.md)

## Boundary Notes

- Beta access 상태 vocabulary는 `active`, `notActive`, `checkFailed`를 따른다.
- [next] ONB step status vocabulary는 `pending`, `complete`, `blocked`, `error`를 따른다.

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:260`
- Contracts: [onboarding_session_contract.toml](../contracts/onboarding_session_contract.toml), [access_unlock_contract.toml](../contracts/access_unlock_contract.toml)
- Flows: [access_unlock_flow.md](../flows/access_unlock_flow.md), [onboarding_session_flow.md](../flows/onboarding_session_flow.md)
