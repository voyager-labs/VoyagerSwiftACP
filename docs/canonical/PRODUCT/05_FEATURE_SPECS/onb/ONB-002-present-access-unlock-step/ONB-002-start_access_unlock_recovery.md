---
interaction_id: "ONB-002-start_access_unlock_recovery"
interaction_type: "command"
feature: "Present Access Unlock Step"
category_key: "ONB"
feature_id: "ONB-002"
status: "shipped"
phase: "now"
summary: "<<AI>> 사용자가 잠금 해제 실패 상태에서 로그인, Core License 구매, beta code 2주 trial 등록, 접근 상태 새로고침, 문의 또는 재시도 경로 중 하나로 진입하도록 안내"
related_region: "onboarding_window.access_unlock_screen"
menu: "-"
shortcut: "-"
---

# Start Access Unlock Recovery

## Intent

- 사용자가 이메일과 토큰을 입력하고 Check 버튼을 눌러 gateway에 beta access 검증을 요청하도록 처리한다.
- [next] 앱 잠금 해제 실패 상태에서 사용자가 막힌 이유에 맞는 회복 경로로 진입하도록 처리한다.
- [next] ONB-002는 recovery entry point를 제공하고, 계정 로그인·결제·beta code 2주 trial·internal test entitlement 생성 자체는 외부 Auth/Billing/Entitlement flow에 위임한다.

## Trigger / Entry Points

- 사용자가 Beta Access step에서 이메일과 토큰을 입력하고 Check 버튼을 누를 때 호출된다.
- [next] 사용자가 Access Unlock step에서 Sign In, Buy Core License, Enter Beta Code, Refresh Access, Contact Support, Retry 중 하나를 선택할 때 호출된다.
- [next] [ONB-002-show_access_unlock_status](ONB-002-show_access_unlock_status.md)가 차단 상태와 허용 CTA를 표시한 뒤 사용자가 CTA를 실행할 때 호출된다.

## Preconditions

- 현재 온보딩 step이 Beta Access이어야 한다.
- 이메일과 토큰 필드에 값이 입력되어 있어야 한다.
- [next] `access_status`가 `complete` 상태가 아니거나, 사용자가 명시적으로 Retry를 선택한 상태여야 한다.
- [next] 선택한 recovery action이 현재 정책과 사용자 상태에서 허용되어야 한다.

## Expected Outcome

- Check 버튼을 누르면 이메일과 토큰이 gateway에 전달되어 beta access 검증이 수행된다.
- 검증 결과는 [ONB-002-apply_access_unlock_result](ONB-002-apply_access_unlock_result.md)에 반영된다.
- 검증 중에는 Check 버튼이 비활성화되고 로딩 상태가 표시된다.
- [next] Sign In CTA는 Auth account login 경로를 열고, 로그인 완료 후 온보딩의 Access Unlock step으로 돌아온다.
- [next] 구매 CTA는 로그인된 계정 기준 Core License 구매 경로를 연다.
- [next] Enter Beta Code CTA는 로그인된 계정에 beta code를 제출해 2주 trial entitlement를 등록하는 경로를 연다.
- [next] Refresh Access CTA는 로그인된 계정의 `access_status`를 다시 확인한다.
- [next] Retry는 `access_status` 재조회로 이어지고 결과는 [ONB-002-apply_access_unlock_result](ONB-002-apply_access_unlock_result.md)에 반영된다.

## State Changes

- 검증 요청 시작 시각, 이메일, 토큰 값을 Beta Access step state에 기록한다.
- 검증 실행 중에는 중복 실행을 막기 위해 pending 상태를 표시한다.
- [next] 선택한 recovery action, 시작 시각, 시작 결과를 Access Unlock step state에 기록한다.
- [next] 외부 flow로 이동하는 action은 온보딩 세션을 유지하고 current step을 Access Unlock으로 보존한다.

## User-visible Feedback

- Check 버튼을 누르면 검증 진행 상태를 표시하고 버튼이 비활성화된다.
- 검증 실패 시 사유에 해당하는 `BetaAccessReason` 메시지를 표시한다.
- [next] 선택한 CTA가 처리 중이면 loading 또는 disabled 상태를 표시한다.
- [next] 외부 로그인 또는 구매 경로로 이동하는 경우 사용자가 온보딩으로 돌아와 Refresh Access 또는 Retry를 실행할 수 있음을 표시한다.
- [next] beta code 제출 중에는 처리 상태를 표시하고, 성공 후 Refresh Access를 통해 `beta_code_trial_active` 결과를 반영한다.
- [next] 허용되지 않은 recovery action은 실행하지 않고 현재 상태에 맞는 대체 경로를 표시한다.
- [next] 문의 경로는 사용자가 support context를 이해할 수 있도록 현재 `access_status`를 함께 전달할 수 있어야 한다.

## Edge Cases / Failure Handling

- 이메일이나 토큰이 누락된 경우 검증을 요청하지 않고 입력 필드 오류를 표시한다.
- 네트워크 연결이 없으면 검증을 시도하지 않고 네트워크 오류를 표시한다.
- gateway가 `invalidCredentials`, `invalidRequest`, `invalidGatewayUrl` 등의 오류를 반환하면 해당 사유를 표시한다.
- [next] 외부 로그인 또는 결제 창 열기에 실패하면 온보딩을 닫지 않고 오류와 Retry를 표시한다.
- [next] 계정 로그인 완료 후에도 entitlement가 없으면 구매 또는 문의 경로를 보여준다.
- [next] beta code가 잘못되었거나 이미 사용된 경우 Access Unlock step을 유지하고 오류와 재입력 경로를 표시한다.
- [next] revoked/refunded 상태에서는 재시도를 무조건 허용하지 않고 server policy result를 따른다.
- [next] 사용자가 recovery flow에서 돌아오지 않아도 온보딩 세션은 재개 가능해야 한다.

## Acceptance Criteria

- [ ] 이메일과 토큰을 입력하고 Check 버튼을 누르면, gateway에 beta access 검증 요청이 전송되어야 한다.
- [ ] 검증 중에는 Check 버튼이 비활성화되고 진행 상태가 표시되어야 한다.
- [ ] 이메일이나 토큰이 누락된 상태에서 Check를 누르면, 검증 요청 없이 입력 오류가 표시되어야 한다.
- [ ] [next] 로그인된 계정이 없는 상황에서 사용자가 Sign In을 실행하면, 계정 로그인 경로가 열리고 온보딩은 Access Unlock step을 유지해야 한다.
- [ ] [next] 로그인된 계정에서 `access_status`가 `none`인 상황에서 사용자가 Buy Core License를 실행하면, 해당 계정 기준 구매 경로가 열리고 온보딩은 Access Unlock step을 유지해야 한다.
- [ ] [next] 로그인된 계정에서 사용자가 beta code를 제출하면, 외부 beta code 등록 경로가 열리고 완료 후 `access_status` 재조회 결과가 Access Unlock `step_completion_state`에 반영되어야 한다.
- [ ] [next] Refresh Access 또는 Retry를 실행한 상황에서 `access_status` 재조회가 성공하면, 새 결과가 Access Unlock `step_completion_state`에 반영되어야 한다.
- [ ] [next] 외부 recovery 경로 열기에 실패한 상황에서 CTA를 실행하면, 온보딩 창을 유지하고 재시도 가능한 오류를 표시해야 한다.

## Permissions / Dependencies

- Gateway beta access 검증 API가 필요하다.
- 네트워크 연결이 필요하다.
- [next] Auth/Billing/Entitlement layer의 계정 로그인, 구매, beta code 2주 trial 등록, 접근 상태 새로고침 entry point가 필요하다.
- [next] 네트워크 연결과 외부 브라우저 또는 앱 내 결제 surface를 열 수 있어야 한다.
- 관련 UI region: `onboarding_window.access_unlock_screen`

## Observability / Analytics

- Check 버튼 탭
- gateway beta access 검증 성공/실패
- [next] recovery CTA 선택
- [next] recovery action 성공/실패
- [next] Retry 성공/실패

## Related Interactions

- [ONB-002-apply_access_unlock_result](ONB-002-apply_access_unlock_result.md)
- [ONB-002-show_access_unlock_status](ONB-002-show_access_unlock_status.md)

## Boundary Notes

- Beta access 상태 vocabulary는 `active`, `notActive`, `checkFailed`를 따른다.
- [next] ONB step status vocabulary는 `pending`, `complete`, `blocked`, `error`를 따른다.

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:261`
- Contracts: [onboarding_session_contract.toml](../contracts/onboarding_session_contract.toml), [access_unlock_contract.toml](../contracts/access_unlock_contract.toml)
- Flows: [access_unlock_flow.md](../flows/access_unlock_flow.md), [onboarding_session_flow.md](../flows/onboarding_session_flow.md)
