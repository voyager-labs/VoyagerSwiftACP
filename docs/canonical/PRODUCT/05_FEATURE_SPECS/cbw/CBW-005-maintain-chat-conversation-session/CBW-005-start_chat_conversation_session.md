---
interaction_id: "CBW-005-start_chat_conversation_session"
interaction_type: "background"
feature: "Maintain Chat Conversation Session"
category_key: "CBW"
feature_id: "CBW-005"
status: "기획 완료"
summary: "현재 맥락 기반 대화에 진입하거나 첫 요청을 보내기 전에 현재 대화 세션을 만들고 초기 상태를 설정한다."
related_region: "-"
menu: "-"
shortcut: "-"
---

# Start Chat Conversation Session

## Intent

- 현재 맥락 기반 대화를 새로 시작할 수 있도록 현재 대화용 chat session을 생성한다.
- 첫 request부터 이후 turn history가 같은 흐름으로 이어지도록 기본 session container를 만든다.

## Trigger / Entry Points

- contextual chat에 처음 진입해 아직 활성 chat session이 없을 때 호출된다.
- 사용자가 기존 대화를 복원하지 않고 새 session으로 시작해야 하는 명시적 경우에 호출된다.

## Preconditions

- 현재 맥락과 연결된 기존 active chat session이 없거나, 새 session 생성이 필요한 상태
- session state를 저장할 수 있는 local persistence 또는 in-memory store가 준비된 상태

## Expected Outcome

- 새 chat session id와 초기 session state가 생성되어야 한다.
- 새 대화의 user-visible status는 `new_session`으로 설정되어야 한다.
- 이후 요청은 해당 session을 기준으로 이어갈 수 있어야 한다.

## State Changes

- chat session record가 생성된다.
- chat session의 user-visible status가 `new_session`으로 설정된다.
- active session pointer가 새 chat session을 가리키도록 준비된다.

## User-visible Feedback

- 사용자는 이전 turn history 대신 빈 입력창이 있는 새 대화 시작 상태를 확인할 수 있어야 한다.
- 이전 대화를 복원하지 않고 새 대화를 시작했다는 결과를 인지할 수 있어야 한다.

## Edge Cases / Failure Handling

- 복원 가능한 chat session이 있지만 새 session 시작이 명시된 경우 기존 session을 덮어쓰지 말아야 한다.
- session 생성이 실패하면 즉시 요청 실행으로 넘어가면 안 된다.
- 현재 맥락이 비어 있어도 session 자체는 생성 가능해야 한다.

## Acceptance Criteria

- [ ] 활성 chat session이 없는 상황에서, 새 session 시작을 수행하면, 현재 대화용 chat session record가 생성되고 user-visible status가 `new_session`으로 설정되어야 한다.
- [ ] 복원 가능한 기존 session이 있는 상황에서, 새 session 시작이 명시되지 않았다면, 무조건 새 session으로 대체되면 안 된다.
- [ ] session 생성이 실패한 상황에서, 새 session 시작을 수행하면, failure가 노출되고 이후 turn continuity 흐름이 진행되지 않아야 한다.

## Permissions / Dependencies

- session store와 현재 맥락 binding metadata가 필요하다.

## Observability / Analytics

- session start 이벤트
- `new_session` vs `restored_session` ratio
- session creation failure count

## Related Interactions

- [CBW-005-continue_chat_conversation_session](CBW-005-continue_chat_conversation_session.md)
- [CBW-005-restore_chat_conversation_session](CBW-005-restore_chat_conversation_session.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:172`
- Contracts: [chat_session_contract.toml](../contracts/chat_session_contract.toml)
- Flows: [chat_session_restore_flow.md](../flows/chat_session_restore_flow.md), [contextual_chat_request_flow.md](../flows/contextual_chat_request_flow.md)
