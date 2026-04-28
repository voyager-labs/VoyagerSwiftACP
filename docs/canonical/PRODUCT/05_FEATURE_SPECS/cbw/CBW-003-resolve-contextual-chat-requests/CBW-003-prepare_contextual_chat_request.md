---
interaction_id: "CBW-003-prepare_contextual_chat_request"
interaction_type: "background"
feature: "Resolve Contextual Chat Requests"
category_key: "CBW"
feature_id: "CBW-003"
status: "기획 완료"
summary: "현재 컨텍스트 스냅샷, 이전 대화 이력이 연결된 대화 세션, 활성 모델 선택에 따라 정해진 프로바이더 연결 정보, 요청 메시지를 결합해 현재 대화 요청의 실행 입력을 확정한다."
related_region: "-"
menu: "-"
shortcut: "-"
---

# Prepare Contextual Chat Request

## Intent

- 실행에 필요한 입력을 현재 request의 실행 가능한 입력으로 정규화한다.
- request preparation 단계에서 `request_context_locked` 상태의 context snapshot, turn history가 연결된 chat session, `model_selected` 상태의 active model, active provider, request message를 결합해 현재 request의 실행 입력을 확정한다.

## Trigger / Entry Points

- snapshot 고정 직후 현재 request의 실행 입력을 확정할 때 호출된다.
- regenerate나 next turn submit 모두 동일한 request preparation path를 사용한다.

## Preconditions

- immutable context snapshot이 존재하는 상태
- active chat session과 `model_selected` 상태의 active model, active provider를 조회할 수 있는 상태
- 실행 대상 request message가 유효한 상태

## Expected Outcome

- provider 호출에 필요한 request message, context snapshot, turn history가 연결된 chat session, active model, active provider가 현재 request의 실행 입력으로 확정되어야 한다.
- 필수 실행 정보가 누락되면 request preparation 단계에서 외부 호출 전에 차단되거나 허용된 축소 정책만 적용되어야 한다.

## State Changes

- request 실행에 필요한 입력이 누락 없이 확정된다.
- 확정된 실행 입력 구성과 excluded context metadata가 request에 연결된다.

## User-visible Feedback

- 성공 시 별도 사용자 피드백보다 후속 `processing` 상태로 자연스럽게 이어져야 한다.
- 오류가 발생하면 어떤 조건이 충족되지 않았는지 설명하는 후속 `failed` 상태 표시로 연결할 수 있어야 한다.

## Edge Cases / Failure Handling

- active model이 전송 직전에 바뀌면 마지막으로 확정된 active model만 실행 입력 구성에 반영해야 한다.
- chat session의 turn history가 너무 길면 최소 continuity를 유지하는 범위에서 축약해야 한다.
- context snapshot이 비어 있어도 request message만으로 실행 가능한 정책이면 request preparation은 계속되어야 한다.

## Acceptance Criteria

- [ ] context snapshot, active chat session, `model_selected` 상태의 active model, active provider가 준비된 상황에서 request preparation을 수행하면, 실행 가능한 요청 입력이 확정되어야 한다.
- [ ] 필수 실행 정보가 누락된 상황에서 request preparation을 수행하면, 외부 호출 전에 오류가 감지되고 후속 `failed` 상태 표시로 이어져야 한다.
- [ ] turn history가 길어 축약이 필요한 상황에서 request preparation을 수행하면, 최소 continuity를 보존하는 범위 내에서만 history가 포함되어야 한다.

## Permissions / Dependencies

- [CBW-002-capture_request_context_snapshot](../CBW-002-manage-request-context/CBW-002-capture_request_context_snapshot.md), [CBW-005-start_chat_conversation_session](../CBW-005-maintain-chat-conversation-session/CBW-005-start_chat_conversation_session.md), [CBW-005-continue_chat_conversation_session](../CBW-005-maintain-chat-conversation-session/CBW-005-continue_chat_conversation_session.md), [CBW-004-show_active_chat_provider_and_model](../CBW-004-manage-active-chat-provider-model/CBW-004-show_active_chat_provider_and_model.md)의 상태를 참조한다.
- provider별 request contract를 알고 있어야 한다.

## Observability / Analytics

- request preparation success/error
- prepared input size or token estimate
- history truncation count

## Related Interactions

- [CBW-003-generate_contextual_chat_response](CBW-003-generate_contextual_chat_response.md)
- [CBW-003-show_request_resolution_failure](CBW-003-show_request_resolution_failure.md)
- [CBW-003-stream_contextual_chat_response](CBW-003-stream_contextual_chat_response.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:165`
- Contracts: [request_context_contract.toml](../contracts/request_context_contract.toml), [chat_session_contract.toml](../contracts/chat_session_contract.toml), [model_selection_contract.toml](../contracts/model_selection_contract.toml), [request_lifecycle.toml](../contracts/request_lifecycle.toml)
- Flows: [chat_provider_model_selection_flow.md](../flows/chat_provider_model_selection_flow.md), [contextual_chat_request_flow.md](../flows/contextual_chat_request_flow.md), [request_context_management_flow.md](../flows/request_context_management_flow.md)
