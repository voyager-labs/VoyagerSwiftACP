---
interaction_id: "SET-007-restore_ai_provider_connection_status"
interaction_type: "background"
feature: "Manage AI Connections"
category_key: "SET"
feature_id: "SET-007"
status: "기획 완료"
summary: "앱 재실행 또는 설정 진입 시 저장된 프로바이더 연결 상태를 복원·재확인해 프로바이더 카탈로그 항목의 상태와 동작을 갱신한다."
related_region: "settings_window.settings_body.tab_ai.provider_list_area"
menu: "-"
shortcut: "-"
---

# Restore AI Provider Connection Status

## Intent

- 앱 재실행이나 Settings AI 탭 재진입 뒤에도 각 `provider` row가 신뢰 가능한 연결 상태를 다시 계산하게 한다.
- 저장된 연결 정보와 현재 빌드 정보를 비교해 row를 `checking_status`에서 최종 status로 정리한다.

## Trigger / Entry Points

- 앱 기동 완료 후 AI 탭이 처음 표시될 때 자동으로 호출된다.
- 설정 화면이 다시 활성화되거나 앱이 포그라운드로 복귀해 status 재확인이 필요할 때 호출된다.

## Preconditions

- 현재 빌드 기준 `provider_catalog` 정보가 준비되어야 한다.
- 저장된 연결 정보 또는 그 부재를 row별로 판정할 수 있어야 한다.
- provider 상태를 재확인할 수 있는 검증 수단에 접근할 수 있어야 한다.

## Expected Outcome

- status 재확인 대상 row는 먼저 `checking_status`로 진입한 뒤 최종적으로 `connected`, `not_verified`, `connection_failed`, `unavailable` 중 하나로 정리되어야 한다.
- 유효한 연결은 `connected`, 검증된 연결 부재는 `not_verified`, 재확인 실패는 `connection_failed`, 현재 빌드에서 연결 불가한 row는 `unavailable`로 표시되어야 한다.
- 최종 status에 맞춰 primary action은 `Disconnect`, `Connect`, `Reconnect`, 비활성화 상태 중 하나로 갱신되어야 한다.
- default provider 설정 UI와 `Last used` 보조 표시는 노출하지 않아야 한다.

## State Changes

- 재확인 대상 row는 먼저 `checking_status`로 전환된다.
- 유효한 인증 정보가 확인되면 row는 `connected`로 바뀌고, 검증된 연결이 없으면 `not_verified`로 바뀐다.
- 검증 과정이 실패하면 row는 `connection_failed`로 정리되고, 현재 빌드에서 연결 UI에 노출할 수 없으면 `unavailable`로 정리된다.
- 마지막으로 사용한 provider 기억값은 최종 status가 `connected`일 때만 유지하고, 그 외 status에서는 정리하거나 무효화한다.

## User-visible Feedback

- 재확인 중 row는 `checking_status` badge 또는 `Checking status...` 메시지를 보여줘야 한다.
- 복원 완료 후 목록은 각 row를 최종 status badge와 primary action으로 갱신해야 한다.
- `connection_failed` row는 failure badge와 `Reconnect` action을 보여줘야 한다.
- `unavailable` row는 `Unavailable in this build` 안내를 보여주고 연결 가능한 row처럼 보이면 안 된다.
- 마지막으로 사용한 provider가 있더라도 default 설정 UI나 `Last used` 보조 표시는 노출하지 않는다.

## Edge Cases / Failure Handling

- 저장된 인증 정보가 손상되었거나 만료되었으면 row는 `connection_failed`로 정리하고 `Reconnect` 경로를 제공해야 한다.
- 네트워크 또는 인증 서비스 장애로 조회를 끝내지 못해도 성공으로 가정하면 안 되며, row는 `connection_failed`로 정리되어야 한다.
- 일부 row만 조회 실패하더라도 다른 row는 자신의 최종 status(`connected`, `not_verified`, `unavailable`)를 유지해야 한다.
- 현재 빌드에서 더 이상 연결 UI에 노출할 수 없는 provider는 `unavailable`로 정리되어야 한다.
- 마지막으로 사용한 provider 기억값이 남아 있더라도 해당 row가 `connected`가 아니면 기억값을 정리하고 다른 provider를 자동 지정하지 않아야 한다.

## Acceptance Criteria

- [ ] 앱 재실행 또는 AI 탭 진입 상황에서, status 복원을 시작하면, 재확인 대상 row는 먼저 `checking_status`를 표시해야 한다.
- [ ] 유효한 인증 정보가 확인된 상황에서, 재확인이 끝나면, 해당 row는 `connected`로 갱신되어야 한다.
- [ ] 저장된 인증 정보가 없거나 검증된 연결이 없는 상황에서, 재확인이 끝나면, 해당 row는 `not_verified`로 갱신되어야 한다.
- [ ] 저장된 인증 정보가 손상되었거나 네트워크 장애로 검증에 실패한 상황에서, 재확인이 끝나면, 해당 row는 `connection_failed`로 갱신되고 `Reconnect` action이 제공되어야 한다.
- [ ] 현재 빌드에서 연결 UI에 노출할 수 없는 row인 상황에서, 재확인이 끝나면, `unavailable` 안내를 보여주고 정상 연결 action을 제공하지 않아야 한다.
- [ ] 마지막으로 사용한 provider 기억값이 있는 상황에서, 목록을 표시하더라도, 별도 `Last used` 보조 표시는 노출되지 않아야 하며 default provider 선택 UI도 보이지 않아야 한다.

## Permissions / Dependencies

- 저장된 provider 인증 정보에 접근할 수 있어야 한다.
- provider별 상태를 재확인할 수 있는 검증 수단이 필요하다.
- 앱 기동 이벤트 또는 화면 진입 이벤트를 트리거로 받을 수 있어야 한다.
- status vocabulary와 최종 action 정책은 [ai_provider_connection_contract.toml](../contracts/ai_provider_connection_contract.toml)을 따른다.

## Observability / Analytics

- 복원 실행 빈도
- provider별 조회 성공/실패 비율
- `checking_status` 진입 빈도
- 복원 후 최종 status 분포(`connected`, `not_verified`, `connection_failed`, `unavailable`)

## Related Interactions

- [SET-007-connect_ai_provider](SET-007-connect_ai_provider.md)
- [SET-007-disconnect_ai_provider](SET-007-disconnect_ai_provider.md)
- [SET-007-show_ai_provider_list](SET-007-show_ai_provider_list.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:244`
- Contracts: [ai_provider_connection_contract.toml](../contracts/ai_provider_connection_contract.toml)
- Flows: [ai_provider_connection_flow.md](../flows/ai_provider_connection_flow.md)
