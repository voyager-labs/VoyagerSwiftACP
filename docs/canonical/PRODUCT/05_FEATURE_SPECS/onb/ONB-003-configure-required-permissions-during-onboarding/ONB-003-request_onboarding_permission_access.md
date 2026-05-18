---
interaction_id: "ONB-003-request_onboarding_permission_access"
interaction_type: "command"
feature: "Configure Required Permissions During Onboarding"
category_key: "ONB"
feature_id: "ONB-003"
status: "shipped"
phase: "now"
summary: "<<AI>> 사용자가 온보딩 중 시스템 설정 열기 또는 헬퍼 폴더 접근 권한 요청을 실행하도록 처리하고 실패 시 재시도 가능한 오류를 표시"
related_region: "onboarding_window.permission_screen"
menu: "-"
shortcut: "-"
---

# Request Onboarding Permission Access

## Intent

- 사용자가 온보딩 중 필요한 권한을 직접 부여할 수 있도록 Full Disk Access 시스템 설정 이동 또는 헬퍼 폴더 접근 권한 요청을 실행한다.
- 권한 요청 action은 ONB-003 step completion을 갱신하기 위한 entry point이며, 실제 권한 승인 여부는 refresh 결과로 판정한다.

## Trigger / Entry Points

- 사용자가 Permissions step에서 Open System Settings를 선택할 때 호출된다.
- 사용자가 Grant Helper Folder Access를 선택할 때 호출된다.
- 사용자가 권한 오류 상태에서 Retry를 선택할 때 호출될 수 있다.

## Preconditions

- 현재 온보딩 step이 Permissions이어야 한다.
- 요청하려는 권한이 이미 granted가 아니어야 한다.
- macOS 시스템 설정 열기 또는 헬퍼 폴더 접근 요청 기능을 호출할 수 있어야 한다.

## Expected Outcome

- Full Disk Access 요청은 macOS 시스템 설정의 적절한 권한 화면을 열고 온보딩은 Permissions step에 남아야 한다.
- 헬퍼 폴더 접근 요청은 사용자가 권한을 부여할 수 있는 folder access flow를 시작해야 한다.
- 요청 시작 이후 사용자가 앱으로 돌아오면 [ONB-003-refresh_onboarding_permission_status](ONB-003-refresh_onboarding_permission_status.md)가 권한 상태를 다시 확인해야 한다.
- 요청 실행 실패는 온보딩 세션을 종료하지 않고 Retry 가능한 오류로 표시되어야 한다.

## State Changes

- 요청한 권한 유형, 요청 시작 시각, 요청 결과를 Permissions step state에 기록한다.
- 권한 요청 중에는 해당 CTA를 pending/disabled 상태로 표시한다.
- 요청 action 자체만으로 step을 complete 처리하지 않고 refresh 결과가 granted일 때 complete로 갱신한다.

## User-visible Feedback

- 시스템 설정 또는 folder access flow가 열리는 동안 진행 상태를 표시한다.
- 사용자가 앱으로 돌아온 뒤 권한 상태를 다시 확인 중임을 표시한다.
- 실행 실패 시 실패 이유와 Retry CTA를 표시한다.
- 이미 granted인 권한에 대해서는 중복 요청 대신 완료 상태를 표시한다.

## Edge Cases / Failure Handling

- 시스템 설정 URL 열기에 실패하면 Full Disk Access 권한 설명과 Retry를 표시한다.
- 사용자가 folder access dialog를 취소하면 missing 상태를 유지하고 다시 요청할 수 있게 한다.
- 권한 요청 중 앱이 종료되어도 재실행 시 Permissions step에서 상태를 재확인한다.
- 두 권한 중 하나만 granted이면 step은 `blocked` 상태를 유지한다.

## Acceptance Criteria

- [ ] Full Disk Access가 missing인 상황에서 사용자가 Open System Settings를 실행하면, 시스템 설정 경로가 열리고 온보딩은 Permissions step을 유지해야 한다.
- [ ] 헬퍼 폴더 접근 권한이 missing인 상황에서 사용자가 Grant Helper Folder Access를 실행하면, folder access 요청 flow가 시작되어야 한다.
- [ ] 사용자가 권한 요청 dialog를 취소하면, 해당 권한은 missing 상태로 남고 Retry 가능한 CTA가 표시되어야 한다.
- [ ] 권한 요청을 실행한 상황에서 refresh 결과가 아직 확인되지 않았으면, Next가 enabled 상태가 아니어야 한다.

## Permissions / Dependencies

- macOS Full Disk Access 시스템 설정 경로를 열 수 있어야 한다.
- 헬퍼 폴더 접근 권한 요청 flow가 필요하다.
- VoyagerHelper가 Desktop/Documents/Downloads 접근 권한을 필요로 한다.
- 관련 UI region: `onboarding_window.permission_screen`

## Observability / Analytics

- 권한 요청 시작/실패
- dialog 취소

## Related Interactions

- [ONB-003-refresh_onboarding_permission_status](ONB-003-refresh_onboarding_permission_status.md)
- [ONB-003-show_onboarding_permission_status](ONB-003-show_onboarding_permission_status.md)

## Boundary Notes

- ONB step status vocabulary는 `pending`, `complete`, `blocked`, `error`를 따른다.

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:264`
- Contracts: [onboarding_session_contract.toml](../contracts/onboarding_session_contract.toml), [permission_readiness_contract.toml](../contracts/permission_readiness_contract.toml)
- Flows: [onboarding_session_flow.md](../flows/onboarding_session_flow.md), [permission_readiness_flow.md](../flows/permission_readiness_flow.md)
