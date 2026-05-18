---
interaction_id: "CBW-001-submit_chat_request"
interaction_type: "command"
feature: "Manage Chat Request Lifecycle"
category_key: "CBW"
feature_id: "CBW-001"
status: "기획 완료"
summary: "Chat Field에 입력한 메시지와 현재 요청 컨텍스트를 기준으로 새 chat request 실행을 시작한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.chat_field"
menu: "-"
shortcut: "Enter"
---

# Submit Chat Request

## Intent

- 사용자가 입력한 request message를 현재 request context와 함께 실행 가능한 chat request로 확정한다.
- 전송 시점의 draft 입력 상태를 실행 상태로 넘기고 후속 fulfillment 흐름을 시작한다.

## Trigger / Entry Points

- Chat Field에서 전송 버튼을 누를 때 호출된다.
- Chat Field가 focus 상태이고 전송 가능한 preconditions가 충족된 경우에만 `Enter`로 요청을 제출할 수 있다.
- 재생성이 아닌 신규 user turn을 시작할 때 호출된다.

## Preconditions

- Chat Pane이 열려 있고 Chat Field가 현재 입력 focus를 가진 상태
- Chat Field에 공백이 아닌 request message가 존재하는 상태
- 현재 active request가 중복 제출을 막을 정도로 blocking 상태가 아니어야 함
- 요청에 반영할 current request context, active session, active model selection을 최소한 조회 가능한 상태

## Expected Outcome

- 새 user request가 생성되고 message list에 즉시 반영되어야 한다.
- draft request context가 snapshot 고정 단계로 넘어가고 request preparation 흐름이 시작되어야 한다.
- 사용자는 제출 직후 해당 요청이 `processing` 상태로 전환된 것을 확인할 수 있어야 한다.
- 전송 직후 Chat Field는 다음 request message를 바로 입력할 수 있는 준비 상태가 되어야 한다.

## State Changes

- draft request message가 제출된 request 실행 입력의 일부로 고정된다.
- 입력창은 전송 직후 비워지고, 입력 focus는 Chat Field로 돌아오거나 유지되어 다음 입력을 받을 수 있는 상태로 전환된다.
- 요청 lifecycle state가 `draft` 또는 idle에서 `processing`으로 전환된다.

## User-visible Feedback

- 긴 request message는 Chat Field 안에서 여러 줄로 줄바꿈되어야 하며, 가로 스크롤이나 텍스트 잘림 없이 입력 내용을 확인할 수 있어야 한다.
- 제출한 user message가 즉시 message area에 나타나야 한다.
- 동시에 `processing` indicator가 표시되어 응답 생성이 시작되었음을 알려야 한다.
- 제출이 막히는 경우에는 막힌 이유와 해소 방법을 바로 보여줘야 한다.

## Edge Cases / Failure Handling

- 입력이 공백뿐이면 request를 만들지 않고 전송이 차단되어야 한다.
- 이미 cancellable한 active request가 있는 동안 병렬 제출이 허용되지 않는 정책이면 중복 제출을 막아야 한다.
- 현재 request context 일부가 해석되지 않아도 전송 자체는 가능하되, 제외된 context는 snapshot 단계에서 기록되어야 한다.

## Acceptance Criteria

- [ ] 사용자가 Chat Field에 유효한 메시지를 입력한 상황에서 전송을 수행하면, 새 user request가 생성되고 `processing` 상태가 시작되어야 한다.
- [ ] Chat Field가 focus 상태이고 전송 가능한 preconditions가 충족된 상황에서 사용자가 `Enter`를 누르면, submit button과 동일하게 새 user request가 생성되어야 한다.
- [ ] 사용자가 유효한 메시지를 전송하면, Chat Field가 비워지고 입력 focus가 Chat Field로 돌아오거나 유지되어 다음 메시지를 바로 입력할 수 있어야 한다.
- [ ] 사용자가 긴 request message를 입력하면, Chat Field는 입력 내용을 여러 줄로 줄바꿈해 보여줘야 하며 가로 스크롤이나 텍스트 잘림이 발생하면 안 된다.
- [ ] 입력이 비어 있는 상황에서 사용자가 전송을 수행하면, request가 생성되지 않아야 하고 전송 불가 상태가 사용자에게 설명되어야 한다.
- [ ] Chat Field가 focus 상태가 아니거나 submit preconditions가 충족되지 않은 상황에서 사용자가 `Enter`를 눌러도, request가 생성되지 않아야 하며 오작동으로 간주되면 안 된다.
- [ ] 일부 context가 제외되는 상황에서 사용자가 전송을 수행하면, 요청 실행은 이어지되 제외된 context가 후속 상태 또는 메타데이터에 반영되어야 한다.

## Permissions / Dependencies

- [CBW-002-capture_request_context_snapshot](../CBW-002-manage-request-context/CBW-002-capture_request_context_snapshot.md), [CBW-003-prepare_contextual_chat_request](../CBW-003-resolve-contextual-chat-requests/CBW-003-prepare_contextual_chat_request.md)에 의존한다.
- active model selection과 session state를 조회할 수 있어야 한다.
- 요청 실행은 연결된 provider가 사용 가능한 상태여야 한다.

## Observability / Analytics

- request submit 이벤트
- 입력 길이 및 context 항목 수
- 제출 차단 사유
- submit 이후 first-token 또는 failure까지 걸린 시간

## Related Interactions

- [CBW-001-cancel_active_chat_request](CBW-001-cancel_active_chat_request.md)
- [CBW-001-open_contextual_chat](CBW-001-open_contextual_chat.md)
- [CBW-001-regenerate_chat_response](CBW-001-regenerate_chat_response.md)
- [CBW-001-show_request_processing_state](CBW-001-show_request_processing_state.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:155`
- Contracts: [request_lifecycle.toml](../contracts/request_lifecycle.toml)
- Flows: [contextual_chat_request_flow.md](../flows/contextual_chat_request_flow.md), [request_context_management_flow.md](../flows/request_context_management_flow.md)
