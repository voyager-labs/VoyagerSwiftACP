---
interaction_id: "SET-007-connect_ai_provider"
interaction_type: "command"
feature: "Manage AI Connections"
category_key: "SET"
feature_id: "SET-007"
status: "기획 완료"
summary: "프로바이더 카탈로그 항목에서 연결 또는 다시 연결을 시작해 해당 프로바이더의 지원 연결 방식에 맞는 연결 흐름으로 진입한다."
related_region: "settings_window.settings_body.tab_ai.provider_list_area"
menu: "-"
shortcut: "-"
---

# Connect AI Provider

## Intent

- 사용자가 개별 provider row에서 연결을 시작할 때 별도 연결 방식 선택 UI를 거치지 않고 바로 연결 흐름에 진입할 수 있게 한다.
- `Connect`와 `Reconnect`를 같은 interaction으로 다루고, row status를 예측 가능한 방식으로 갱신한다.

## Trigger / Entry Points

- provider 목록 row의 `Connect` 또는 `Reconnect` action을 선택할 때 호출된다.

## Preconditions

- 연결할 provider가 row action으로 명확히 지정되어야 한다.
- 대상 row가 현재 빌드에서 연결 가능한 상태여야 하며 `unavailable`이면 안 된다.
- 대상 row가 `not_verified` 또는 `connection_failed`여야 한다.
- 대상 row가 이미 `connect_in_progress`이면 새 연결 시도를 시작하면 안 된다.
- 대상 row의 연결 방식 정보가 현재 빌드에서 해석 가능해야 한다.

## Expected Outcome

- 사용자가 `Connect` 또는 `Reconnect`를 실행하면 대상 row는 먼저 `connect_in_progress`로 진입해야 한다.
- 연결이 성공하면 대상 row는 `connected`로 바뀌고, primary action은 `Disconnect`로 갱신되어야 한다.
- 연결이 실패하면 대상 row는 `connection_failed`로 정리되고, primary action은 `Reconnect`로 갱신되어야 한다.
- row가 허용한 연결 방식이 `OAuth`면 외부 인증 진입으로 이어지고, `API key`면 같은 row 문맥의 inline 입력으로 이어져야 한다.
- default provider 설정 UI와 `Last used` 보조 표시는 이 interaction에서 노출하지 않아야 한다.

## State Changes

- 선택한 provider row는 `connect_in_progress`로 전환된다.
- 성공한 연결은 같은 row를 `connected`로 바꾸고, 실패한 연결은 `connection_failed`로 정리한다.
- `Connect`와 `Reconnect`는 모두 같은 status 전이(`not_verified` 또는 `connection_failed` -> `connect_in_progress`)를 사용한다.
- 이 interaction만으로 마지막으로 사용한 provider 기억값을 새 default처럼 확정하지는 않는다.

## User-visible Feedback

- connect action 직후 시스템은 대상 row를 `connect_in_progress`로 표시하고 중복 클릭을 막아야 한다.
- 연결 방식이 `OAuth`인 row는 외부 인증 진입 안내를 보여줘야 한다.
- 연결 방식이 `API key`인 row는 별도 상세 패널 없이 같은 row 안의 inline 입력 필드와 제출 action을 보여줘야 한다.
- 연결이 성공하면 같은 row는 `connected` badge와 `Disconnect` action을 보여줘야 한다.
- 연결이 실패하면 같은 row는 `connection_failed` badge와 `Reconnect` action을 보여줘야 한다.

## Edge Cases / Failure Handling

- 이미 `connect_in_progress`인 row에 다시 action을 눌러도 중복 연결 시도를 만들지 않아야 한다.
- `unavailable` row에는 `Connect` 또는 `Reconnect`를 노출하지 않거나 비활성화해야 한다.
- 연결 방식 정보를 확인할 수 없으면 row는 `connect_in_progress`에 머물면 안 되며 `connection_failed`로 정리되어야 한다.
- 사용자가 다른 row를 조작하더라도 기존 시도는 대상 provider row 기준으로 독립적으로 관리되어야 한다.
- OAuth 또는 API key 제출이 실패하면 긴 실패 문구 대신 `connection_failed` badge와 `Reconnect` action 중심으로 되돌려야 한다.

## Acceptance Criteria

- [ ] `not_verified` row인 상황에서, `Connect`를 누르면, 대상 row는 `connect_in_progress`를 거쳐 연결 흐름으로 진입해야 한다.
- [ ] `connection_failed` row인 상황에서, `Reconnect`를 누르면, 대상 row는 같은 interaction으로 다시 `connect_in_progress`에 진입해야 한다.
- [ ] 연결 방식이 `OAuth`인 row인 상황에서, 연결을 시작하면, 외부 인증 흐름으로 이어져야 한다.
- [ ] 연결 방식이 `API key`인 row인 상황에서, 연결을 시작하면, 같은 row 안의 inline 입력 필드로 key 제출을 요구해야 한다.
- [ ] 연결이 성공한 상황에서, 대상 row를 보면, `connected`로 바뀌고 `Disconnect` action이 표시되어야 한다.
- [ ] 연결이 실패한 상황에서, 대상 row를 보면, `connection_failed`로 바뀌고 `Reconnect` action이 표시되어야 한다.

## Permissions / Dependencies

- provider별 연결 방식 메타데이터가 필요하다.
- OAuth와 API key 분기는 모두 별도 제품 interaction으로 분리하지 않고 같은 connect 흐름 안에서 처리한다.
- status 전이와 primary action 정책은 [ai_provider_connection_contract.toml](../contracts/ai_provider_connection_contract.toml)을 따른다.

## Observability / Analytics

- provider별 connect 시도
- provider별 연결 방식 분기 결과
- connect 이후 provider별 `connected` 전환율
- connect 이후 provider별 `connection_failed` 전환율

## Related Interactions

- [SET-007-disconnect_ai_provider](SET-007-disconnect_ai_provider.md)
- [SET-007-restore_ai_provider_connection_status](SET-007-restore_ai_provider_connection_status.md)
- [SET-007-show_ai_provider_list](SET-007-show_ai_provider_list.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:242`
- Contracts: [ai_provider_connection_contract.toml](../contracts/ai_provider_connection_contract.toml)
- Flows: [ai_provider_connection_flow.md](../flows/ai_provider_connection_flow.md)
