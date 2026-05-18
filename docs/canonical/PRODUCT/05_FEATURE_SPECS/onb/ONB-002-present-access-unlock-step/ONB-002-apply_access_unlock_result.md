---
interaction_id: "ONB-002-apply_access_unlock_result"
interaction_type: "background"
feature: "Present Access Unlock Step"
category_key: "ONB"
feature_id: "ONB-002"
status: "shipped"
phase: "now"
summary: "<<AI>> Auth/Entitlement layer가 반환한 접근 상태 결과를 온보딩 스텝 완료 여부와 오류 표시 상태에 반영"
related_region: "onboarding_window.access_unlock_screen"
menu: "-"
shortcut: "-"
---

# Apply Access Unlock Result

## Intent

- Gateway가 반환한 beta access 검증 결과를 온보딩의 Beta Access step 완료 여부와 오류 표시 상태로 변환한다.
- [next] Auth/Entitlement layer가 반환한 `access_status`를 온보딩의 Access Unlock `step_completion_state`와 오류 표시 상태로 변환한다.
- [next] ONB-001이 다음 step 이동 여부를 일관되게 판단할 수 있도록 server-canonical 결과를 `progress_snapshot`에 반영한다.

## Trigger / Entry Points

- 사용자가 이메일과 토큰을 입력하고 Check 버튼을 눌러 gateway 검증이 완료될 때 호출된다.
- [next] Access Unlock step 진입 시 `access_status` 조회가 완료될 때 호출된다.
- [next] 사용자가 Retry를 실행한 뒤 `access_status` 조회가 완료될 때 호출된다.
- [next] 계정 로그인 또는 구매 flow에서 돌아온 뒤 `access_status`를 다시 확인할 때 호출된다.

## Preconditions

- 온보딩 세션과 Beta Access step state가 존재해야 한다.
- Gateway 검증 응답이 성공 또는 실패로 정규화되어 있어야 한다.
- [next] Auth account session 상태와 Auth/Entitlement layer의 응답이 성공, 실패, 취소, timeout 중 하나로 정규화되어 있어야 한다.
- [next] 동시에 여러 조회가 진행된 경우 최신 요청을 식별할 수 있어야 한다.

## Expected Outcome

- `active`는 Beta Access step `complete`로 반영된다.
- `notActive`는 오류 사유(`BetaAccessReason`)와 함께 진행 차단 상태로 반영된다.
- `checkFailed`는 Retry 가능한 오류로 반영되며 `complete`로 승격하지 않는다.
- [next] `core_license_active`, `beta_code_trial_active`, `internal_test_active`는 Access Unlock step `complete`로 반영된다.
- [next] `none`, `trial_expired`, `revoked`, `refunded`는 Access Unlock step `blocked`로 반영된다.
- [next] 조회 실패, timeout, 취소는 `complete`로 승격하지 않고 Retry 가능한 `error` state로 반영된다.
- [next] ONB-001은 갱신된 completion state를 기준으로 Next enablement와 step transition을 계산한다.

## State Changes

- `BetaAccessStatus`, `BetaAccessReason`, lastCheckedAt을 step state에 저장한다.
- 이전 오류가 새 성공 결과로 해소되면 오류 상태를 지운다.
- [next] `access_status`, completion state, lastCheckedAt, lastError, allowedRecoveryActions를 `progress_snapshot`에 저장한다.
- [next] 최신 요청보다 오래된 응답은 무시하고 현재 화면 상태를 되돌리지 않는다.

## User-visible Feedback

- 성공 결과는 [ONB-002-show_access_unlock_status](ONB-002-show_access_unlock_status.md)를 통해 완료 상태로 표시된다.
- 실패 결과는 사유별 메시지와 함께 표시된다.
- [next] 차단 결과는 현재 허용된 recovery action 목록과 함께 표시된다.

## Edge Cases / Failure Handling

- gateway가 알 수 없는 오류를 반환하면 `checkFailed`와 Retry를 표시한다.
- 네트워크 오류로 검증이 실패하면 과거 성공 상태만으로 진행시키지 않는다.
- 이미 사용된 토큰은 `alreadyUsed` 사유로 처리한다.
- 기기 불일치는 `deviceMismatch` 사유로 처리한다.
- [next] 응답이 알 수 없는 `access_status`를 포함하면 `blocked`와 Retry/`error` state로 처리한다.
- [next] network offline 상태에서 조회가 실패하면 snapshot의 과거 `complete` 상태만으로 진행시키지 않는다.
- [next] revoked/refunded 결과는 이전 `complete` snapshot보다 우선한다.
- [next] 앱이 background로 이동해 요청이 취소되면 current step을 보존하고 재진입 시 다시 확인한다.

## Acceptance Criteria

- [ ] gateway 검증 결과가 `active`로 반환된 상황에서 결과가 적용되면, Beta Access step이 완료 상태로 저장되고 Next가 enabled 상태가 되어야 한다.
- [ ] gateway 검증 결과가 `notActive`로 반환된 상황에서 결과가 적용되면, 실패 사유가 표시되고 Next가 비활성화되어야 한다.
- [ ] gateway 검증이 실패한 상황에서 결과가 적용되면, 기존 성공 상태만으로 다음 step에 진입하지 않아야 한다.
- [ ] [next] 로그인된 계정의 `access_status`가 `core_license_active`로 반환된 상황에서 결과가 적용되면, Access Unlock step이 `complete`로 저장되어야 한다.
- [ ] [next] `access_status`가 `trial_expired`로 반환된 상황에서 결과가 적용되면, Access Unlock step이 `blocked`로 저장되고 Next가 비활성화되어야 한다.
- [ ] [next] 오래된 요청 결과가 최신 요청 이후 도착하면, 최신 요청 기준의 step state가 유지되어야 한다.

## Permissions / Dependencies

- Gateway beta access 검증 API 응답이 필요하다.
- [next] Auth/Entitlement layer의 server-canonical `access_status`가 필요하다.
- [next] ONB-001 `progress_snapshot` store에 `step_completion_state`를 저장할 수 있어야 한다.
- 관련 UI region: `onboarding_window.access_unlock_screen`

## Observability / Analytics

- gateway 검증 결과 적용
- [next] `access_status` result 적용
- [next] `complete`/`blocked`/`error` state 전환

## Related Interactions

- [ONB-002-show_access_unlock_status](ONB-002-show_access_unlock_status.md)
- [ONB-002-start_access_unlock_recovery](ONB-002-start_access_unlock_recovery.md)

## Boundary Notes

- Beta access 상태 vocabulary는 `active`, `notActive`, `checkFailed`를 따른다.
- [next] ONB step status vocabulary는 `pending`, `complete`, `blocked`, `error`를 따른다.

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:262`
- Contracts: [onboarding_session_contract.toml](../contracts/onboarding_session_contract.toml), [access_unlock_contract.toml](../contracts/access_unlock_contract.toml)
- Flows: [access_unlock_flow.md](../flows/access_unlock_flow.md), [onboarding_session_flow.md](../flows/onboarding_session_flow.md)
