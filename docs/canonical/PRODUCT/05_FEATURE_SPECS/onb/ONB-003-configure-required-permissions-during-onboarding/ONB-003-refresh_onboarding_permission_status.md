---
interaction_id: "ONB-003-refresh_onboarding_permission_status"
interaction_type: "background"
feature: "Configure Required Permissions During Onboarding"
category_key: "ONB"
feature_id: "ONB-003"
status: "shipped"
phase: "now"
summary: "<<AI>> 앱 활성화 또는 재시도 후 Full Disk Access와 헬퍼 폴더 접근 권한 상태를 다시 확인해 온보딩 완료 조건에 반영"
related_region: "onboarding_window.permission_screen"
menu: "-"
shortcut: "-"
---

# Refresh Onboarding Permission Status

## Intent

- 앱 활성화, Retry, 권한 요청 완료 이후 Full Disk Access와 헬퍼 폴더 접근 권한 상태를 다시 확인해 Permissions `step_completion_state`에 반영한다.
- ONB-003은 stale 권한 snapshot을 그대로 신뢰하지 않고 현재 OS/앱 권한 상태를 기준으로 온보딩 진행 가능 여부를 계산한다.

## Trigger / Entry Points

- Permissions step에 진입할 때 자동으로 호출된다.
- 사용자가 권한 요청 flow에서 앱으로 돌아올 때 호출된다.
- 앱이 foreground로 돌아올 때 호출된다.
- 사용자가 Refresh 또는 Retry를 실행할 때 호출된다.

## Preconditions

- 온보딩 세션과 Permissions step state가 존재해야 한다.
- Full Disk Access와 헬퍼 폴더 접근 권한 상태를 조회할 수 있어야 한다.
- 여러 refresh 요청이 동시에 실행될 경우 최신 요청을 식별할 수 있어야 한다.

## Expected Outcome

- 두 권한이 모두 granted이면 Permissions step이 complete로 저장된다.
- 하나라도 missing이면 Permissions step은 `blocked`로 저장되고 missing 권한별 CTA가 유지된다.
- 조회 실패는 complete로 승격하지 않고 Retry 가능한 error state로 저장된다.
- ONB-001은 갱신된 completion state를 기준으로 Next enablement와 step transition을 계산한다.

## State Changes

- 권한별 status, completion state, lastCheckedAt, lastError를 step state에 저장한다.
- 이전 error state는 새 성공 결과로 해소되면 제거한다.
- 오래된 refresh 응답은 최신 요청 기준 상태를 덮어쓰지 않는다.

## User-visible Feedback

- refresh 중에는 권한 상태 확인 중임을 표시한다.
- granted로 전환된 권한은 즉시 완료 표시로 갱신한다.
- missing 또는 error 상태는 권한별 next action과 함께 표시한다.
- 부분 실패 시 확인된 권한 상태와 실패한 조회를 구분해 표시한다.

## Edge Cases / Failure Handling

- 사용자가 시스템 설정에서 권한을 부여하지 않고 돌아오면 missing 상태를 유지한다.
- OS가 권한 변경을 즉시 반영하지 않으면 Retry를 허용하고 Next는 비활성화한다.
- 헬퍼 폴더 접근 권한이 revoked되면 이전 granted snapshot보다 새 missing 상태를 우선한다.
- refresh 중 앱이 background로 이동하면 current step을 보존하고 재진입 시 다시 확인한다.
- `resolveFullDiskAccessStatus`는 Full Disk Access가 `needsAction`이고 사용자가 시도한 적이 있으면 `denied`로 처리한다.

## Acceptance Criteria

- [ ] 두 권한이 모두 granted인 상황에서 refresh가 완료되면, Permissions step이 complete로 저장되고 Next가 enabled 상태가 되어야 한다.
- [ ] Full Disk Access만 granted인 상황에서 refresh가 완료되면, 헬퍼 폴더 접근 권한 CTA가 유지되고 Next는 disabled 상태여야 한다.
- [ ] 권한 조회가 실패한 상황에서 refresh가 완료되면, step이 complete로 승격되지 않고 Retry 가능한 오류가 표시되어야 한다.
- [ ] 오래된 refresh 결과가 최신 refresh 이후 도착하면, 최신 요청 기준의 권한 상태가 유지되어야 한다.

## Permissions / Dependencies

- Full Disk Access 상태 조회 API 또는 OS 권한 상태 확인 로직이 필요하다.
- 헬퍼 폴더 접근 권한 상태 확인 로직이 필요하다.
- VoyagerHelper가 Desktop/Documents/Downloads 접근 권한을 필요로 한다.
- 앱 foreground 전환 감지가 필요하다.
- ONB-001은 갱신된 completion state를 기준으로 step transition을 계산한다.
- 관련 UI region: `onboarding_window.permission_screen`

## Observability / Analytics

- 권한별 granted/missing 전환

## Related Interactions

- [ONB-003-request_onboarding_permission_access](ONB-003-request_onboarding_permission_access.md)
- [ONB-003-show_onboarding_permission_status](ONB-003-show_onboarding_permission_status.md)

## Boundary Notes

- ONB step status vocabulary는 `pending`, `complete`, `blocked`, `error`를 따른다.

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:265`
- Contracts: [onboarding_session_contract.toml](../contracts/onboarding_session_contract.toml), [permission_readiness_contract.toml](../contracts/permission_readiness_contract.toml)
- Flows: [onboarding_session_flow.md](../flows/onboarding_session_flow.md), [permission_readiness_flow.md](../flows/permission_readiness_flow.md)
