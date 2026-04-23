---
interaction_id: "CBW-005-restore_chat_conversation_session"
interaction_type: "background"
feature: "Maintain Chat Conversation Session"
category_key: "CBW"
feature_id: "CBW-005"
status: "기획 완료"
summary: "기존 대화로 돌아오면 직전 대화 세션과 이전 턴 히스토리를 복원하고, 복원할 수 없으면 새 대화 세션을 시작한다."
related_region: "-"
menu: "-"
shortcut: "-"
---

# Restore Chat Conversation Session

## Intent

- 이전에 진행 중이던 contextual chat을 다시 열 때 직전 chat session과 turn history를 복원한다.
- 복원 결과에 따라 `restored_session`, `restore_failed`, `rebind_required`를 판정하고, 복원을 이어갈 수 없으면 새 session 시작 경로로 넘긴다.

## Trigger / Entry Points

- chat pane 재오픈, 현재 맥락 복귀, 앱 재개 후 active chat 복원이 필요할 때 호출된다.

## Preconditions

- 복원 가능한 chat session record가 존재하는 상태
- 세션과 연관된 message history를 읽을 수 있는 상태
- 현재 맥락과 session binding을 비교할 수 있는 상태

## Expected Outcome

- 직전 chat session id, turn history, active model selection, 최소 session metadata가 복원되어야 한다.
- 복원에 성공하면 user-visible status는 `restored_session`으로 판정되어야 한다.
- message history가 불완전하거나 session record가 더 이상 유효하지 않으면 `restore_failed`로 판정한 뒤 `new_session` 시작 경로로 이어져야 한다.
- 현재 맥락과 session binding이 맞지 않으면 `rebind_required`로 판정한 뒤 stale한 session을 활성화하지 않고 `new_session` 시작 경로로 이어져야 한다.

## State Changes

- 복원 성공 시 chat session의 user-visible status가 `restored_session`으로 판정된다.
- 복원 성공 시 turn history와 최소 session metadata가 현재 chat session에 채워진다.
- message history 불완전, session record 손상, 만료 등의 사유가 있으면 user-visible status가 `restore_failed`로 판정된다.
- 현재 맥락과 session binding이 맞지 않으면 user-visible status가 `rebind_required`로 판정된다.
- `restore_failed` 또는 `rebind_required`가 판정되면 기존 session record는 active session으로 승격되지 않고 `new_session` fallback으로 이어진다.

## User-visible Feedback

- 복원 성공 시 사용자는 기존 turn history가 다시 열린 것을 통해 같은 대화 흐름을 이어간다고 인지할 수 있어야 한다.
- `restore_failed` 또는 `rebind_required`가 발생하면 기존 turn history가 그대로 남아 있으면 안 된다.
- 복원 실패 또는 재연결 필요 상황은 한 번의 안내 후 빈 입력창이 있는 새 대화 시작 상태로 전환되어야 한다.

## Edge Cases / Failure Handling

- session record는 있지만 일부 message history만 신뢰할 수 있으면 부분 복원으로 보정하지 말고 `restore_failed`로 판정한 뒤 새 session으로 폴백해야 한다.
- 현재 맥락이 예전과 달라 현재 session binding이 어긋나면 `rebind_required`로 판정한 뒤 새 session으로 폴백해야 한다.
- 복원 대상 session이 너무 오래되었거나 더 이상 유효하지 않으면 `restore_failed`로 판정하고 새 session으로 전환해야 한다.

## Acceptance Criteria

- [ ] 복원 가능한 chat session이 있는 상황에서, restore를 수행하면, 직전 chat session과 turn history가 chat pane에 복원되고 user-visible status가 `restored_session`으로 판정되어야 한다.
- [ ] session 일부만 신뢰 가능한 상황에서, restore를 수행하면, 불완전한 history를 active session으로 쓰지 말고 `restore_failed`로 판정한 뒤 새 session 시작 경로로 폴백해야 한다.
- [ ] 현재 맥락과 기존 session binding이 맞지 않는 상황에서, restore를 수행하면, 기존 session을 그대로 active로 두지 말고 `rebind_required`로 판정한 뒤 새 session 시작 경로로 폴백해야 한다.

## Permissions / Dependencies

- session persistence와 message history store에 의존한다.
- 현재 맥락 확인 UI는 [CBW-002-show_request_context](../CBW-002-manage-request-context/CBW-002-show_request_context.md)와 연결될 수 있어야 한다.
- fallback path는 [CBW-005-start_chat_conversation_session](CBW-005-start_chat_conversation_session.md)과 연결되어야 한다.

## Observability / Analytics

- session restore 이벤트
- `restored_session` / `restore_failed` / `rebind_required` 비율
- restore latency

## Related Interactions

- [CBW-005-continue_chat_conversation_session](CBW-005-continue_chat_conversation_session.md)
- [CBW-005-start_chat_conversation_session](CBW-005-start_chat_conversation_session.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:174`
- Contracts: [chat_session_contract.toml](../contracts/chat_session_contract.toml)
- Flows: [chat_session_restore_flow.md](../flows/chat_session_restore_flow.md), [contextual_chat_request_flow.md](../flows/contextual_chat_request_flow.md)
