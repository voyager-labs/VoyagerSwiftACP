---
interaction_id: "ONB-003-show_onboarding_permission_status"
interaction_type: "display"
feature: "Configure Required Permissions During Onboarding"
category_key: "ONB"
feature_id: "ONB-003"
status: "shipped"
phase: "now"
summary: "<<AI>> 온보딩 권한 요청 스크린에서 Full Disk Access와 헬퍼 폴더 접근 권한의 현재 상태, 필요 사유, 다음 액션을 표시"
related_region: "onboarding_window.permission_screen"
menu: "-"
shortcut: "-"
---

# Show Onboarding Permission Status

## Intent

- 사용자가 Voyager 첫 실행에 필요한 Full Disk Access와 헬퍼 폴더 접근 권한 상태를 이해하고, 다음 액션을 선택할 수 있도록 표시한다.
- ONB-003은 온보딩 중 권한 준비 상태를 소유하고, OS 권한 부여 자체는 macOS 시스템 설정과 파일 선택 권한 flow에 의존한다.
- `isComplete`는 `fullDiskAccessStatus == .granted` AND `helperFolderAccessStatus == .granted`일 때 true이다.

## Trigger / Entry Points

- ONB-001이 Permissions step을 현재 step으로 표시할 때 호출된다.
- 앱이 foreground로 돌아오거나 사용자가 Retry/Refresh를 실행해 권한 상태가 다시 계산될 때 호출된다.
- [ONB-003-refresh_onboarding_permission_status](ONB-003-refresh_onboarding_permission_status.md)가 새 상태를 반영한 뒤 화면을 다시 그릴 때 호출된다.

## Preconditions

- 온보딩 세션이 시작되어 있고 current step이 Permissions이어야 한다.
- Full Disk Access 상태와 헬퍼 폴더 접근 권한 상태를 조회할 수 있어야 한다.

## Expected Outcome

- Full Disk Access와 헬퍼 폴더 접근 권한 각각의 상태가 granted, missing, checking, error 중 하나로 표시된다.
- 두 권한이 모두 granted이면 Permissions step은 complete로 표시되고 Next가 enabled 상태가 된다.
- 하나라도 missing 또는 error이면 Next는 disabled 상태가 되고 필요한 액션이 표시된다.
- 사용자는 Open System Settings, Grant Helper Folder Access, Refresh 중 현재 상태에 맞는 CTA를 볼 수 있어야 한다.
- Full Disk Access 상태가 `needsAction`이고 사용자가 권한 요청을 시도한 적이 있으면 `denied` 상태로 표시된다.

## State Changes

- display interaction은 OS 권한 자체와 온보딩 상태를 변경하지 않는다.
- 조회된 권한 상태를 기준으로 Permissions step view state와 completion state를 계산한다.

## User-visible Feedback

- 각 권한의 현재 상태와 필요한 이유를 분리해 표시한다.
- 이미 granted인 권한은 완료 상태로 표시하고 다시 요청하지 않는다.
- missing 상태인 권한은 실행 가능한 CTA를 표시한다.
- 상태 확인 실패는 Retry 가능한 오류로 표시하고 권한 완료로 간주하지 않는다.
- Launch at Login 토글이 권한 화면에 표시된다.

## Edge Cases / Failure Handling

- macOS 시스템 설정을 열 수 없는 환경이면 Full Disk Access CTA 실패 메시지를 표시한다.
- 헬퍼 폴더 접근 권한이 revoked되면 이전 granted snapshot보다 새 missing 상태를 우선한다.
- 권한 상태 조회가 지연되면 Next를 enabled로 미리 전환하지 않는다.
- 권한 상태가 부분적으로만 확인되면 확인된 권한과 실패한 권한을 구분해 표시한다.
- Full Disk Access가 `needsAction`이고 사용자가 시도한 적이 있으면 `resolveFullDiskAccessStatus`가 `denied`로 처리한다.

## Acceptance Criteria

- [ ] Permissions step에 진입한 상황에서 두 권한이 모두 granted이면, 완료 상태와 enabled Next가 표시되어야 한다.
- [ ] Full Disk Access가 missing인 상황에서 화면이 표시되면, Open System Settings CTA와 disabled Next가 표시되어야 한다.
- [ ] 헬퍼 폴더 접근 권한이 missing인 상황에서 화면이 표시되면, Grant Helper Folder Access CTA가 표시되어야 한다.
- [ ] 권한 상태 확인이 실패하면, 권한 완료로 처리하지 않고 Retry 가능한 오류를 표시해야 한다.
- [ ] Full Disk Access가 `needsAction`이고 사용자가 이미 시도한 상황에서 화면이 표시되면, `denied` 상태로 표시되어야 한다.

## Permissions / Dependencies

- Full Disk Access 상태 조회와 macOS 시스템 설정 열기 기능이 필요하다.
- 헬퍼 폴더 접근 권한 요청 flow가 필요하다.
- VoyagerHelper가 Desktop/Documents/Downloads 접근 권한을 필요로 한다.
- Launch at Login 기능이 필요하다.
- ONB-001은 ONB-003이 계산한 `step_completion_state`를 읽어 다음 step 이동 여부를 결정한다.
- 관련 UI region: `onboarding_window.permission_screen`

## Observability / Analytics

- 권한별 상태 조회 성공/실패

## Related Interactions

- [ONB-003-refresh_onboarding_permission_status](ONB-003-refresh_onboarding_permission_status.md)
- [ONB-003-request_onboarding_permission_access](ONB-003-request_onboarding_permission_access.md)

## Boundary Notes

- ONB step status vocabulary는 `pending`, `complete`, `blocked`, `error`를 따른다.

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:263`
- Contracts: [onboarding_session_contract.toml](../contracts/onboarding_session_contract.toml), [permission_readiness_contract.toml](../contracts/permission_readiness_contract.toml)
- Flows: [onboarding_session_flow.md](../flows/onboarding_session_flow.md), [permission_readiness_flow.md](../flows/permission_readiness_flow.md)
