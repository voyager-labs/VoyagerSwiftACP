---
interaction_id: "SET-007-disconnect_ai_provider"
interaction_type: "command"
feature: "Manage AI Connections"
category_key: "SET"
feature_id: "SET-007"
status: "기획 완료"
summary: "프로바이더 카탈로그에서 해당 프로바이더 연결을 해제하고 이후 요청에서 해당 프로바이더 인증 정보가 사용되지 않도록 상태를 갱신한다."
related_region: "settings_window.settings_body.tab_ai.provider_list_area"
menu: "-"
shortcut: "-"
---

# Disconnect AI Provider

## Intent

- 사용자가 `connected` 상태의 `provider` row를 명시적으로 해제하고, 이후 요청에서 그 연결이 계속 사용되지 않게 한다.
- 연결 해제 이후 row를 `not_verified`로 되돌려 재연결 동선을 명확히 한다.

## Trigger / Entry Points

- AI 탭 provider 목록 row에서 `Disconnect` 액션을 선택할 때 호출된다.

## Preconditions

- 대상 provider가 row action으로 명확히 지정되어야 한다.
- 해당 row가 `connected` 상태여야 한다.
- 연결 해제 전 사용자 확인 모달을 표시해야 한다.
- 대상 row가 이미 `disconnect_in_progress`이면 새 해제 시도를 시작하면 안 된다.

## Expected Outcome

- 사용자가 연결 해제를 확정하면 대상 row는 먼저 `disconnect_in_progress`로 진입해야 한다.
- 연결 해제가 성공하면 저장된 연결 정보가 제거되고 대상 row는 `not_verified`로 바뀌어야 한다.
- 연결 해제가 실패하거나 사용자가 확인 모달을 취소하면 대상 row는 `connected`를 유지해야 한다.
- 연결 해제 후에도 default provider를 별도로 지정하거나 다른 provider를 자동 대체하면 안 된다.

## State Changes

- 사용자가 확인을 누르면 대상 row는 `disconnect_in_progress`로 전환된다.
- 성공 시 저장된 provider 인증 정보가 제거되고 row는 `not_verified`로 정리된다.
- 실패 또는 취소 시 row는 다시 `connected`로 돌아가며, 끊긴 것처럼 보이면 안 된다.
- 마지막으로 사용한 provider 기억값이 해당 row를 가리키고 있었다면 성공 시에만 제거하거나 무효화한다.

## User-visible Feedback

- 사용자가 `Disconnect`를 누르면 먼저 확인 모달을 보여주고, 확정 이후에만 `disconnect_in_progress`를 표시해야 한다.
- 성공 시 대상 row는 `not_verified` badge와 `Connect` action으로 갱신되어야 한다.
- 실패 시 대상 row는 `connected`를 유지한 채 실패 안내를 보여줘야 한다.
- 취소 시 row status와 action은 변경되지 않고 `connected`를 유지해야 한다.
- 연결 해제 후에도 마지막으로 사용한 provider 정보는 별도 UI badge로 노출하지 않아야 한다.

## Edge Cases / Failure Handling

- 대상 row가 이미 `disconnect_in_progress`이면 추가 해제 action을 받아도 중복 요청을 만들지 않아야 한다.
- 해제 API 응답이 지연되면 row는 `disconnect_in_progress`를 유지하며 완료 전까지 `not_verified`로 앞서 보이면 안 된다.
- 연결 해제가 실패하면 사용자에게 실패 사실을 알려야 하지만 최종 row status는 `connected`를 유지해야 한다.
- 사용자가 확인 모달에서 취소하면 실제 해제는 수행되지 않고 row는 `connected`를 유지해야 한다.
- 현재 사용 중인 provider를 해제한 경우에도 다른 provider를 자동으로 default 지정하면 안 된다.

## Acceptance Criteria

- [ ] `connected` row인 상황에서, `Disconnect`를 확정하면, 대상 row는 `disconnect_in_progress`를 거쳐 `not_verified`로 바뀌어야 한다.
- [ ] 연결 해제에 성공한 상황에서, 대상 row를 보면, 목록에 남아 있으면서 `Connect` action으로 되돌아가야 한다.
- [ ] 연결 해제 직후인 상황에서, 이후 요청을 실행하면, 해당 provider 인증 정보가 계속 사용되지 않아야 한다.
- [ ] 해제 처리 또는 토큰 폐기 과정이 실패한 상황에서, 대상 row를 보면, 실제로 끊긴 것처럼 `not_verified`로 보이면 안 되고 `connected`를 유지해야 한다.
- [ ] 사용자가 확인 모달에서 연결 해제를 취소한 상황에서, 흐름이 종료되면, 실제 해제는 실행되지 않고 row는 `connected`를 유지해야 한다.
- [ ] 마지막으로 사용한 provider를 해제한 상황에서, 해제가 성공하면, 해당 내부 기억값은 제거되거나 무효화되어야 하며 다른 provider가 자동으로 default 지정되지는 않아야 한다.

## Permissions / Dependencies

- provider별 저장된 인증 정보를 제거하거나 갱신할 수 있어야 한다.
- chat과 request 실행 흐름이 provider 연결 해제 결과를 반영할 수 있어야 한다.
- status 전이와 confirmation 정책은 [ai_provider_connection_contract.toml](../contracts/ai_provider_connection_contract.toml)을 따른다.

## Observability / Analytics

- 연결 해제 시도 횟수
- `disconnect_in_progress` 진입 횟수
- 연결 해제 성공/실패
- 해제 직후 provider 사용 차단 이벤트

## Related Interactions

- [SET-007-connect_ai_provider](SET-007-connect_ai_provider.md)
- [SET-007-restore_ai_provider_connection_status](SET-007-restore_ai_provider_connection_status.md)
- [SET-007-show_ai_provider_list](SET-007-show_ai_provider_list.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:243`
- Contracts: [ai_provider_connection_contract.toml](../contracts/ai_provider_connection_contract.toml)
- Flows: [ai_provider_connection_flow.md](../flows/ai_provider_connection_flow.md)
