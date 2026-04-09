---
interaction_id: "SET-002-request_notifications_permission"
interaction_type: "command"
feature: "Configure General Settings"
category_key: "SET"
feature_id: "SET-002"
status: "아이디어"
summary: "<<AI>> 설정(General)에서 Notifications 권한을 요청하고, 결과에 따라 권한 상태를 표시하며 필요 시 시스템 설정에서 변경할 수 있는 경로를 제공한다."
related_region: "settings_window.settings_body.tab_general"
menu: "-"
shortcut: "-"
---

# Request Notifications Permission

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> 설정 창이 열려 있고 General 탭이 표시된 상태
- <<AI>> 알림 권한 상태를 조회할 수 있는 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 사용자가 알림 권한 프롬프트에서 거부하는 경우
- <<AI>> 과거 거부/결정 완료로 인해 시스템 프롬프트가 다시 표시되지 않는 경우
- <<AI>> OS 설정에서 알림이 전역 차단된 경우
- <<AI>> MDM/보안 정책 등으로 알림 설정 변경이 제한되는 경우

## Acceptance Criteria

- [ ] <<AI>> 설정 창의 General 탭이 표시된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 알림 권한
      요청이 수행되고 결과가 상태로 반영됨.
- [ ] <<AI>> 시스템 프롬프트가 표시 가능한 상태일 때, 사용자가 허용하면, 설정 화면의 상태가
      “허용됨”으로 갱신됨.
- [ ] <<AI>> 시스템 프롬프트에서 사용자가 거부하면, 설정 화면의 상태가 “미허용”으로 갱신되고 알림
      없이 동작하는 제한 사항이 안내됨.
- [ ] <<AI>> 시스템 프롬프트를 다시 표시할 수 없는 상태일 때, 사용자가 해당 인터랙션을 호출하면,
      시스템 설정에서 알림을 변경하는 방법이 안내되고 “시스템 설정 열기”가 제공됨.
- [ ] <<AI>> 전역 차단 상태일 때, 상태를 갱신하면, 전역 차단 안내와 변경 경로가 함께 표시됨.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `229`
