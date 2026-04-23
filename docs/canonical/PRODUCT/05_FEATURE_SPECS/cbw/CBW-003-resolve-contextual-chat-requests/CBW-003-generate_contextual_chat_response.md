---
interaction_id: "CBW-003-generate_contextual_chat_response"
interaction_type: "background"
feature: "Resolve Contextual Chat Requests"
category_key: "CBW"
feature_id: "CBW-003"
status: "기획 완료"
summary: "준비된 대화 요청 실행 입력을 사용해 외부 AI에 요청을 보내 응답 스트림 또는 최종 응답을 생성한다."
related_region: "-"
menu: "-"
shortcut: "-"
---

# Generate Contextual Chat Response

## Intent

- 준비된 request 실행 입력을 외부 AI provider에 실행해 response를 생성한다.
- VOY-235 범위의 핵심 fulfillment 경로를 담당한다.

## Trigger / Entry Points

- request preparation이 완료된 뒤 현재 request의 response 생성을 시작할 때 호출된다.
- regenerate나 일반 next turn 모두 동일한 response 생성 경로를 사용한다.

## Preconditions

- 실행 가능한 request 실행 입력이 존재하는 상태
- 해당 `model_selected` 상태의 active model과 그에 따라 결정된 active provider가 현재 요청에 사용 가능한 상태
- 네트워크와 인증 상태가 요청 실행을 허용하는 상태

## Expected Outcome

- 외부 AI 호출이 시작되고 response stream 또는 최종 response가 후속 display 단계로 전달되어야 한다.
- 오류가 발생하면 error reason이 분류 가능한 형태로 상위 lifecycle에 반환되어야 한다.
- 외부 AI 호출이 시작된 뒤 selected model을 사용할 수 없다고 확인되면, model 관련 오류가 반환되어야 한다.

## State Changes

- 현재 request에 연결된 response 생성이 시작된다.
- 현재 response 생성에 적용되는 active model과 active provider가 고정된다.

## User-visible Feedback

- 사용자에게는 후속 `processing` 상태 표시와 stream display를 통해 실행 중임이 전달되어야 한다.
- 오류 시 재시도 또는 모델 변경 등 다음 행동이 있는 후속 `failed` 상태 표시로 연결되어야 한다.

## Edge Cases / Failure Handling

- 인증 만료, `model_unavailable`, 네트워크 오류는 서로 구분 가능한 error type으로 반환해야 한다.
- dropdown에서 선택이 저장되어 있더라도, provider 호출 과정에서 해당 model을 사용할 수 없으면 그 시점의 model 관련 오류로 처리해야 한다.
- cancel 요청이 들어오면 더 이상 downstream display에 chunk를 공급하지 않아야 한다.
- 빈 response가 반환되거나 provider가 조기 종료해도 empty response 정책 또는 error 처리 정책이 필요하다.

## Acceptance Criteria

- [ ] 실행 가능한 request 실행 입력이 준비된 상황에서 response 생성을 수행하면, 외부 AI 요청이 시작되고 response stream 또는 최종 response가 생성되어야 한다.
- [ ] 인증 또는 연결 상태가 유효하지 않은 상황에서 response 생성을 수행하면, provider 호출 전에 또는 직후에 error reason이 식별 가능하게 반환되어야 한다.
- [ ] 사용자가 선택한 model을 provider 호출 과정에서 사용할 수 없다고 확인된 상황에서 response 생성을 수행하면, 그 시점의 model 관련 오류가 식별 가능하게 반환되어야 한다.
- [ ] 사용자가 response 생성 도중 cancel을 수행한 상황에서는, cancellation 이후 신규 response chunk가 최종 결과로 반영되지 않아야 한다.

## Permissions / Dependencies

- provider SDK/API와 현재 active provider 연결 상태에 의존한다.
- cancellation path는 [CBW-001-cancel_active_chat_request](../CBW-001-manage-chat-request-lifecycle/CBW-001-cancel_active_chat_request.md)와 연결되어야 한다.

## Observability / Analytics

- response 생성 start/end
- time to first token
- response 생성 error type
- `cancelled` response 생성 count

## Related Interactions

- [CBW-003-prepare_contextual_chat_request](CBW-003-prepare_contextual_chat_request.md)
- [CBW-003-show_request_resolution_failure](CBW-003-show_request_resolution_failure.md)
- [CBW-003-stream_contextual_chat_response](CBW-003-stream_contextual_chat_response.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:166`
- Contracts: [model_selection_contract.toml](../contracts/model_selection_contract.toml), [request_lifecycle.toml](../contracts/request_lifecycle.toml)
- Flows: [chat_provider_model_selection_flow.md](../flows/chat_provider_model_selection_flow.md), [contextual_chat_request_flow.md](../flows/contextual_chat_request_flow.md)
