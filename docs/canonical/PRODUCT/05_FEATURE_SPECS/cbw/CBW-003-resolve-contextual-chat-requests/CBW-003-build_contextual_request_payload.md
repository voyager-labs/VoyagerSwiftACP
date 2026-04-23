---
interaction_id: "CBW-003-build_contextual_request_payload"
interaction_type: "background"
feature: "Resolve Contextual Chat Requests"
category_key: "CBW"
feature_id: "CBW-003"
status: "드래프트"
summary: "<<AI>> 현재 request context, `chat_session`, active provider/model, 사용자 입력을 결합해 실행용 payload를 구성한다."
related_region: "-"
menu: "-"
shortcut: "-"
---

# Build Contextual Request Payload

## Intent

- 실행에 필요한 입력을 하나의 provider 호출 payload로 정규화한다.
- request context, `chat_session`, active provider/model, user input을 실행 가능한 계약으로 결합한다.

## Trigger / Entry Points

- snapshot 고정 직후 request execution을 시작할 때 호출된다.
- regenerate나 next turn submit 모두 동일한 payload build path를 사용한다.

## Preconditions

- immutable request snapshot이 존재하는 상태
- active `chat_session`과 active provider/model을 조회할 수 있는 상태
- 실행 대상 user input이 유효한 상태

## Expected Outcome

- provider 호출에 필요한 prompt, context bundle, `chat_session` metadata, model binding이 payload로 완성되어야 한다.
- payload 누락이 있으면 실행 전에 차단하거나 축소 정책을 적용해야 한다.

## State Changes

- request 실행에 필요한 입력이 누락 없이 확정된다.
- payload build 결과와 excluded context metadata가 request에 연결된다.

## User-visible Feedback

- 성공 시 별도 사용자 피드백보다 후속 processing 상태로 자연스럽게 이어져야 한다.
- 실패 시 어떤 조건이 충족되지 않았는지 user-facing failure로 연결할 수 있어야 한다.

## Edge Cases / Failure Handling

- active model이 전송 직전에 바뀌면 마지막으로 확정된 active model만 payload에 반영해야 한다.
- session turn history가 너무 길면 최소 continuity를 유지하는 범위에서 축약해야 한다.
- snapshot이 비어 있어도 user input만으로 실행 가능한 정책이면 payload build는 계속되어야 한다.

## Acceptance Criteria

- [ ] request snapshot, active `chat_session`, active provider/model이 준비된 상황에서 payload build를 수행하면, 실행 가능한 provider 요청 payload가 생성되어야 한다.
- [ ] 필수 실행 정보가 누락된 상황에서 payload build를 수행하면, 외부 호출 전에 실패가 감지되고 후속 failure display로 이어져야 한다.
- [ ] session history가 길어 축약이 필요한 상황에서 payload build를 수행하면, 최소 continuity를 보존하는 범위 내에서만 history가 포함되어야 한다.

## Permissions / Dependencies

- [CBW-002-capture_request_context_snapshot](../CBW-002-manage-request-context/CBW-002-capture_request_context_snapshot.md), [CBW-005-start_chat_conversation_session](../CBW-005-maintain-chat-conversation-session/CBW-005-start_chat_conversation_session.md), [CBW-005-continue_chat_conversation_session](../CBW-005-maintain-chat-conversation-session/CBW-005-continue_chat_conversation_session.md), [CBW-004-show_active_chat_provider_and_model](../CBW-004-manage-active-chat-provider-model/CBW-004-show_active_chat_provider_and_model.md)의 상태를 참조한다.
- provider별 request contract를 알고 있어야 한다.

## Observability / Analytics

- payload build success/failure
- payload size or token estimate
- history truncation count

## Related Interactions

- [CBW-003-generate_contextual_chat_response](CBW-003-generate_contextual_chat_response.md)
- [CBW-003-show_request_resolution_failure](CBW-003-show_request_resolution_failure.md)
- [CBW-003-show_response_references](CBW-003-show_response_references.md)
- [CBW-003-stream_contextual_chat_response](CBW-003-stream_contextual_chat_response.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Contracts: [request_context_contract.toml](../contracts/request_context_contract.toml), [provider_selection_contract.toml](../contracts/provider_selection_contract.toml), [model_selection_contract.toml](../contracts/model_selection_contract.toml)
- Source line: `166`
