---
interaction_id: "CBW-001-open_contextual_chat"
interaction_type: "command"
feature: "Manage Chat Request Lifecycle"
category_key: "CBW"
feature_id: "CBW-001"
status: "기획 완료"
summary: "현재 페이지 또는 선택 맥락을 초기 request context로 반영하기 위해 Inspector Pane을 열고 Chat Mode로 전환한 뒤 요청 입력 준비 상태를 연다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat"
menu: "-"
shortcut: "⌘L"
---

# Open Contextual Chat

## Intent

- 현재 보고 있는 page 또는 selection 맥락을 즉시 초기 request context로 반영하고 AI 대화를 시작할 수 있게 한다.
- 기존 활성 chat session이 있으면 `restored_session` 경로로 이어가고, 없으면 `new_session` 경로에서 새 요청을 입력할 수 있는 chat 준비 상태를 만든다.

## Trigger / Entry Points

- 현재 페이지의 AI 채팅 진입 CTA, context menu에서의 chat 진입 액션, 또는 자연어 라우팅 결과로 chat 진입이 필요할 때 호출된다.
- 사용자가 `⌘L`로 현재 맥락을 유지한 채 contextual chat을 열고 싶을 때 호출된다.
- Inspector Pane이 닫혀 있거나 Chat Mode가 아닌 상태에서도 동일 shortcut으로 진입할 수 있어야 한다.

## Preconditions

- File Manager Window가 열려 있고 현재 page 또는 selection 맥락을 해석할 수 있는 상태
- Inspector Pane에서 Chat Pane을 표시할 수 있는 상태
- 연결 상태가 미완료여도 진입 자체는 허용되며, 이후 상태 피드백을 표시할 수 있어야 함

## Expected Outcome

- Inspector Pane이 닫혀 있었다면 먼저 열려야 한다.
- Inspector Pane의 현재 active mode가 Chat Mode가 아니었다면 Chat Mode로 전환되어야 한다.
- Chat Pane이 열리고 입력 포커스 또는 직전 활성 메시지 위치가 복원되어야 한다.
- 현재 page/selection 기준의 초기 request context가 Chat Field 안의 고정된 current context 영역으로 준비되거나, 기존 chat session 복원 흐름이 시작되어야 한다.
- 연결 미완료 상태라면 chat surface 안에서 연결 불가 원인을 보여주는 error state가 보여야 한다.

## State Changes

- Inspector Pane이 닫혀 있었다면 open state가 `closed`에서 `open`으로 전환된다.
- Inspector Pane의 active mode가 Chat Mode가 아니었다면 Chat Mode로 전환된다.
- 현재 page/selection 맥락에서 파생된 current context entry가 draft request context 안의 고정 위치에 준비되거나, restore 대상 chat session id가 준비된다.
- 신규 진입인지 기존 session 복원인지가 chat state에 기록된다.

## User-visible Feedback

- 사용자는 Inspector Pane이 열리고 Chat Mode로 전환된 결과를 화면에서 확인할 수 있어야 한다.
- 사용자는 Chat Field 안의 고정된 current context 영역에서 현재 page와 selection이 attachment와 구분되어 표시된 결과를 확인할 수 있어야 한다.
- 복원 가능한 chat session이 있으면 기존 session transcript와 입력 가능한 chat state를 표시하고, 없으면 빈 입력창이 있는 새 대화 시작 상태를 표시한다.
- session 복원에 실패한 경우에는 toast로 실패 사실을 한 번 알린 뒤 빈 입력창이 있는 새 대화 시작 상태로 전환되어야 한다.
- 연결이 없거나 사용할 수 없는 상태면 진입 직후 연결 불가 원인과 연결 설정 CTA를 보여준다.

## Edge Cases / Failure Handling

- 현재 page/selection 맥락이 비어 있거나 해석할 수 없어도 chat 진입은 가능해야 하며, 현재 request context item이 없는 상태로 열려야 한다.
- Inspector Pane이 이미 열려 있고 다른 inspector mode가 활성화된 상태라면, 기존 pane을 재생성하지 않고 Chat Mode로만 전환해야 한다.
- 이미 다른 request가 실행 중인 경우에도 chat 진입은 가능하지만 해당 실행 상태를 유지한 채 보여줘야 한다.
- 복원 대상 session이 손상되었거나 더 이상 유효하지 않다면, 복원 실패 사실을 toast로 노출한 뒤 빈 입력창이 있는 새 대화 시작 상태로 전환해야 한다.

## Acceptance Criteria

- [ ] 사용자가 현재 page 또는 selection 맥락이 있는 상황에서 `⌘L`로 contextual chat 진입을 호출하면, Inspector Pane이 닫혀 있었다면 열리고 Chat Mode로 전환된 뒤 Chat Field의 고정된 current context 영역에 현재 맥락 기준의 대화 준비 상태가 보여야 한다.
- [ ] Inspector Pane이 이미 열려 있지만 Chat Mode가 아닌 상황에서 사용자가 contextual chat 진입을 호출하면, 기존 pane을 유지한 채 active mode만 Chat Mode로 전환하고 현재 맥락이 attachment와 구분된 초기 request context로 준비되어야 한다.
- [ ] 복원 가능한 chat session이 있는 상황에서 사용자가 chat 진입을 호출하면, 새 대화를 강제로 만들지 않고 기존 session 복원 흐름이 시작되어야 한다.
- [ ] session restore가 실패하는 상황에서 사용자가 chat 진입을 호출하면, 복원 실패 사실이 toast로 한 번 노출된 뒤 빈 입력창이 있는 새 대화 시작 상태로 전환되어야 한다.
- [ ] 연결이 아직 준비되지 않은 상황에서 사용자가 chat 진입을 호출하면, chat surface 자체는 열리되 연결 불가 이유와 연결 설정 CTA가 함께 보여야 한다.

## Permissions / Dependencies

- Chat Pane surface와 현재 context resolver에 의존한다.
- Inspector Pane open/switch control path에 의존한다.
- 기존 session 복원은 [CBW-005-restore_chat_conversation_session](../CBW-005-maintain-chat-conversation-session/CBW-005-restore_chat_conversation_session.md)에 의존한다.
- 연결 상태 표시는 `SET-007`의 provider 연결 상태를 참조할 수 있어야 한다.

## Observability / Analytics

- chat 진입 시도 이벤트
- chat 진입 source shortcut(`⌘L`) 여부
- 진입 source surface(page action, context menu, routing) 기록
- session reuse 여부
- 진입 직후 연결 불가 상태 노출 수

## Related Interactions

- [CBW-001-cancel_active_chat_request](CBW-001-cancel_active_chat_request.md)
- [CBW-001-regenerate_chat_response](CBW-001-regenerate_chat_response.md)
- [CBW-001-show_request_processing_state](CBW-001-show_request_processing_state.md)
- [CBW-001-submit_chat_request](CBW-001-submit_chat_request.md)

## Boundary Notes

- `⌘I`는 generic inspector pane open/toggle을 위한 인터랙션이며, 그 자체만으로 현재 맥락을 초기 request context로 반영하지 않는다.
- `⌘L`는 contextual chat 진입 인터랙션이며, Inspector Pane open, Chat Mode 전환, 현재 page/selection 기반 current context seed 준비를 하나의 사용자 행동으로 묶는다.

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:154`
- Contracts: [chat_session_contract.toml](../contracts/chat_session_contract.toml), [request_context_contract.toml](../contracts/request_context_contract.toml)
- Flows: [chat_session_restore_flow.md](../flows/chat_session_restore_flow.md), [contextual_chat_request_flow.md](../flows/contextual_chat_request_flow.md), [request_context_management_flow.md](../flows/request_context_management_flow.md)
