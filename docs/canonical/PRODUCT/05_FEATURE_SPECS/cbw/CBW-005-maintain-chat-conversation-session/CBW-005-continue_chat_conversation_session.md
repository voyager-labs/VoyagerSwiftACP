---
interaction_id: "CBW-005-continue_chat_conversation_session"
interaction_type: "background"
feature: "Maintain Chat Conversation Session"
category_key: "CBW"
feature_id: "CBW-005"
status: "기획 완료"
summary: "이전 turn history를 반영해 현재 대화 세션을 다음 요청까지 이어 가도록 갱신하고 최소 연속성을 유지한다."
related_region: "-"
menu: "-"
shortcut: "-"
---

# Continue Chat Conversation Session

## Intent

- 현재 active chat session이 `new_session`이든 `restored_session`이든 다음 turn에서도 이어지도록 session history와 필요한 session state를 갱신한다.
- 이전 turn history를 다음 요청에 반영할 수 있도록 최소 session 연속성 규칙을 유지한다.

## Trigger / Entry Points

- 새 user turn이 제출될 때 또는 assistant response가 완료된 뒤 session continuity를 갱신할 때 호출된다.
- regenerate가 이전 request를 기준으로 실행되어 기준 request 뒤의 후속 turn을 초기화한 뒤, 남은 turn history 기준으로 continuity를 다시 맞출 때 호출된다.

## Preconditions

- 활성 chat session이 존재하는 상태
- 직전 turn 결과를 session history에 반영할 수 있는 상태
- 다음 요청 준비 단계가 이 session continuity 결과를 참조할 수 있는 상태

## Expected Outcome

- 이전 turn history와 필요한 session metadata가 다음 요청에 사용할 수 있는 상태로 갱신되어야 한다.
- session이 너무 커지면 최소 continuity를 유지하는 범위에서만 축약되어야 한다.
- regenerate로 인해 특정 시점 이후 turn이 잘린 경우, 남은 유효 history만 다음 요청 실행 입력에 사용되어야 한다.

## State Changes

- session history가 새 turn을 반영하도록 갱신된다.
- 필요 시 오래된 history 일부가 축약 또는 제외된다.
- regenerate 기준점 뒤의 invalidated turn history가 session continuity 범위에서 제거된다.
- `single_timeline_rewrite` 정책에 따라 branch session은 새로 만들지 않는다.

## User-visible Feedback

- 사용자는 현재 대화가 같은 흐름으로 이어지고 있다는 결과를 확인할 수 있어야 한다.
- 축약이 발생해도 대화가 끊긴 것처럼 느껴지지 않아야 한다.

## Edge Cases / Failure Handling

- 직전 turn이 실패했더라도 session continuity를 어떻게 유지할지 일관된 정책이 필요하다.
- active model selection이 바뀐 직후 다음 turn에서는 이전 history와 새 model selection 조합이 허용되어야 한다.
- history가 너무 커 token budget에 걸리면 oldest turn부터 축약해야 한다.
- regenerate가 과거 request를 기준으로 수행된 경우에도 branch session을 만들지 말고, 단일 active session에서 이후 history를 잘라내는 정책만 허용해야 한다.

## Acceptance Criteria

- [ ] 활성 chat session이 있는 상황에서, continuity 갱신을 수행하면, 다음 요청은 이전 turn history를 반영한 상태로 준비되어야 한다.
- [ ] session history가 너무 큰 상황에서, continuity 갱신을 수행하면, 최소 continuity를 유지하는 범위에서만 history가 축약되어야 한다.
- [ ] 직전 turn 이후 active model selection이 바뀐 상황에서, continuity 갱신을 수행하면, session은 이어지되 다음 요청은 새 model selection 기준으로 준비되어야 한다.
- [ ] regenerate가 과거 request를 기준으로 수행되어 이후 turn이 무효화된 상황에서, continuity 갱신을 수행하면, 잘려 나간 turn은 다음 요청 실행 입력에 포함되지 않아야 한다.

## Permissions / Dependencies

- session history store와 token budget 정책이 필요하다.
- request preparation 단계가 이 갱신 결과를 참조해야 한다.

## Observability / Analytics

- session continue 이벤트
- history truncation count
- session continuity broken count

## Related Interactions

- [CBW-005-restore_chat_conversation_session](CBW-005-restore_chat_conversation_session.md)
- [CBW-005-start_chat_conversation_session](CBW-005-start_chat_conversation_session.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:173`
- Contracts: [chat_session_contract.toml](../contracts/chat_session_contract.toml)
- Flows: [chat_session_restore_flow.md](../flows/chat_session_restore_flow.md), [contextual_chat_request_flow.md](../flows/contextual_chat_request_flow.md)
