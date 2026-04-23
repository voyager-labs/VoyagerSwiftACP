---
interaction_id: "CBW-003-show_request_resolution_failure"
interaction_type: "display"
feature: "Resolve Contextual Chat Requests"
category_key: "CBW"
feature_id: "CBW-003"
status: "기획 완료"
summary: "대화 요청 처리 또는 응답 생성이 실패하면 실패 이유와 재시도 진입점을 메시지 영역에 표시한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.message_area"
menu: "-"
shortcut: "-"
---

# Show Request Resolution Failure

## Intent

- request execution 또는 response 생성 중 오류가 발생해 대상 request가 `failed`로 전환될 때, 사용자가 이해 가능한 error reason을 함께 보여준다.
- 재시도 가능한 경우 기존 request를 다시 실행하는 진입점을 함께 제공한다.

## Trigger / Entry Points

- request preparation, response 생성, stream 처리 중 오류가 발생해 대상 request가 `failed`로 전환될 때 호출된다.
- 복구 가능한 오류와 즉시 `failed`로 이어지는 오류 모두 이 display 경로를 사용한다.

## Preconditions

- 실패 원인 코드 또는 사람이 읽을 수 있는 error message가 존재하는 상태
- message area가 `failed` 상태 bubble 또는 inline error를 렌더링할 수 있는 상태

## Expected Outcome

- 사용자는 실패했다는 사실과 최소한의 실패 이유를 이해할 수 있어야 한다.
- `failed` 상태는 성공 response처럼 보이지 않아야 하며, 어떤 request가 `failed`가 되었는지 식별 가능해야 한다.

## State Changes

- 대상 request가 `failed` 상태로 전환된다.
- error metadata가 request와 message area에 표시되는 error message에 연결된다.

## User-visible Feedback

- 실패 이유와 재시도 가능한지 여부가 함께 보여야 한다.
- 재시도 가능한 오류면 같은 request를 다시 실행하는 `regenerate` 진입점을 함께 보여야 한다.

## Edge Cases / Failure Handling

- 인증 오류, provider connection issue, provider-side model error, unknown error 등 주요 error 유형은 구분 가능할 때만 나눠 보여야 한다.
- partial response 후 오류가 발생해 request가 `failed`가 되면, partial content와 `failed` 상태의 관계가 명확해야 한다.
- 일시적 네트워크 오류는 재시도 가능한 error로 해석할 수 있어야 한다.

## Acceptance Criteria

- [ ] request execution 중 오류가 발생해 대상 request가 `failed`로 전환된 상황에서 `failed` 상태 표시를 수행하면, 사용자는 실패 이유와 재실행 진입점을 이해할 수 있어야 한다.
- [ ] partial response가 일부 표시된 뒤 오류가 발생해 request가 `failed`가 된 상황에서 `failed` 상태 표시를 수행하면, partial content와 `failed` 상태가 함께 구분되어 보여야 한다.
- [ ] 재시도 가능한 오류 상황에서 `failed` 상태 표시를 수행하면, 같은 request를 다시 실행하는 `regenerate` 진입점이 제시되어야 한다.

## Permissions / Dependencies

- error classifier와 message renderer에 의존한다.
- 연결 관련 오류는 `SET-007`의 `connection_failed`, `not_verified`, `unavailable` 상태와 연결될 수 있어야 하며, model 관련 오류는 `CBW-003-generate_contextual_chat_response`에서 반환된 provider-side model error와 연결될 수 있어야 한다.

## Observability / Analytics

- error type distribution
- regenerate entry exposure
- error after partial response count

## Related Interactions

- [CBW-003-prepare_contextual_chat_request](CBW-003-prepare_contextual_chat_request.md)
- [CBW-003-generate_contextual_chat_response](CBW-003-generate_contextual_chat_response.md)
- [CBW-003-stream_contextual_chat_response](CBW-003-stream_contextual_chat_response.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:168`
- Contracts: [request_lifecycle.toml](../contracts/request_lifecycle.toml), [model_selection_contract.toml](../contracts/model_selection_contract.toml), [ai_provider_connection_contract.toml](../../set/contracts/ai_provider_connection_contract.toml)
- Flows: [chat_provider_model_selection_flow.md](../flows/chat_provider_model_selection_flow.md), [contextual_chat_request_flow.md](../flows/contextual_chat_request_flow.md)
