---
interaction_id: "CBW-003-stream_contextual_chat_response"
interaction_type: "display"
feature: "Resolve Contextual Chat Requests"
category_key: "CBW"
feature_id: "CBW-003"
status: "기획 완료"
summary: "생성 중인 응답을 메시지 영역에 점진적으로 표시하고 완료 시 최종 응답으로 확정한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.message_area"
menu: "-"
shortcut: "-"
---

# Stream Contextual Chat Response

## Intent

- 생성 중인 response를 사용자가 기다리는 동안 점진적으로 표시한다.
- 최종 응답이 완성되기 전에도 대화가 진행 중이라는 감각을 제공한다.

## Trigger / Entry Points

- response 생성 단계에서 response chunk 또는 delta가 도착할 때마다 호출된다.
- 이미 표시 중인 response가 있을 때 이어서 갱신된다.

## Preconditions

- 실행 중인 request가 `processing` 상태이고 그 request와 연결된 response stream이 존재하는 상태
- message area가 현재 표시 중인 response를 렌더링할 수 있는 상태

## Expected Outcome

- 응답 chunk가 순서대로 누적되어 하나의 response로 보여야 한다.
- stream이 정상 완료되면 해당 response는 최종 응답으로 남아야 하고, 연결된 request는 `completed` 상태로 전환되어야 한다.

## State Changes

- message area에 표시 중인 response content가 chunk 단위로 확장된다.
- stream이 정상 종료되면 연결된 request가 `completed` 상태로 전환된다.

## User-visible Feedback

- 사용자는 응답이 실제로 생성 중임을 텍스트 누적과 `processing` 상태 표시로 인지할 수 있어야 한다.
- 완료 후에는 더 이상 깜빡이는 loading 표시가 남아 있지 않아야 한다.

## Edge Cases / Failure Handling

- chunk 순서가 어긋나면 최종 출력 순서를 보존해야 한다.
- cancel 이후 도착한 late chunk는 현재 response에 추가하지 않아야 한다.
- stream이 비정상 종료되면 현재까지의 partial content와 후속 error 정보를 함께 처리해야 한다.

## Acceptance Criteria

- [ ] response stream이 도착하는 상황에서 stream display를 수행하면, response는 message area에 점진적으로 누적되어 보여야 한다.
- [ ] stream이 정상 종료되는 상황에서 stream display를 수행하면, 연결된 request는 `completed` 상태로 전환되고 해당 response는 최종 응답으로 남아야 한다.
- [ ] stream 도중 cancel 또는 오류가 발생해 request가 `cancelled` 또는 `failed`로 이어지는 상황에서 stream display를 수행하면, 이후 late chunk는 현재 response에 추가되지 않아야 한다.

## Permissions / Dependencies

- message renderer와 streaming transport에 의존한다.
- 후속 `failed` 상태 표시는 [CBW-003-show_request_resolution_failure](CBW-003-show_request_resolution_failure.md)와 이어져야 한다.

## Observability / Analytics

- stream chunk count
- time to first visible token
- partial-to-final conversion rate

## Related Interactions

- [CBW-003-prepare_contextual_chat_request](CBW-003-prepare_contextual_chat_request.md)
- [CBW-003-generate_contextual_chat_response](CBW-003-generate_contextual_chat_response.md)
- [CBW-003-show_request_resolution_failure](CBW-003-show_request_resolution_failure.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:167`
- Contracts: [request_lifecycle.toml](../contracts/request_lifecycle.toml)
- Flows: [contextual_chat_request_flow.md](../flows/contextual_chat_request_flow.md)
