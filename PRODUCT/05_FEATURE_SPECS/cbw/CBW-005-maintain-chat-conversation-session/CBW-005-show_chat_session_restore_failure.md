---
interaction_id: "CBW-005-show_chat_session_restore_failure"
interaction_type: "display"
feature: "Maintain Chat Conversation Session"
category_key: "CBW"
feature_id: "CBW-005"
status: "드래프트"
summary: "<<AI>> session state를 복원하거나 이어가기 어려운 경우 실패 이유와 새 대화 시작 등 후속 행동을 표시한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.message_area"
menu: "-"
shortcut: "-"
---

# Show Chat Session Restore Failure

## Intent

- session 복원 실패를 사용자에게 설명하고 복구 가능한 다음 행동을 제공한다.
- restore failure를 silent fallback으로 숨기지 않고 토스트, 인라인 배너 등 비차단 피드백을 포함해 명시적으로 다룬다.

## Trigger / Entry Points

- session restore 또는 restore 후 validation에서 실패가 감지될 때 호출된다.

## Preconditions

- 복원 실패 reason이 존재하는 상태
- message area 또는 동등한 위치에 failure state를 노출할 수 있는 상태

## Expected Outcome

- 사용자는 왜 기존 대화를 이어갈 수 없는지 이해하고, retry 또는 새 대화 시작을 선택할 수 있어야 한다.
- restore failure는 일반 request failure와 구분되어야 한다.
- 자동으로 새 session으로 폴백하는 경우에도 실패 사실이 최소 한 번은 드러나야 한다.

## State Changes

- `chat_session`의 user-visible status가 `restore_failed`로 표시된다.
- 후속 CTA로 retry restore를 제안할 수 있고, active path는 `new_session` 시작 경로와 연결된다.

## User-visible Feedback

- failure reason과 함께 새 대화 시작, 다시 시도 같은 후속 행동이 보여야 한다.
- 노출 방식은 modal blocking UI로 제한하지 않으며, 토스트나 인라인 상태 안내처럼 흐름을 막지 않는 피드백일 수 있다.
- 복원 실패 후에도 chat surface 전체가 unusable 상태로 남아 있지 않아야 한다.

## Edge Cases / Failure Handling

- 일부 history만 신뢰 가능한 경우에도 별도 상태를 만들지 말고 `restore_failed` reason detail에서 범위를 구분해야 한다.
- session record 손상과 단순 로딩 실패를 같은 copy로 처리하지 말아야 한다.
- restore failure 직후 자동으로 새 session을 만들더라도 실패 사실은 한 번은 보여야 한다.

## Acceptance Criteria

- [ ] session restore가 실패한 상황에서 failure 표시를 수행하면, 사용자는 실패 이유와 가능한 다음 행동을 이해할 수 있어야 한다.
- [ ] 일부 history만 신뢰 가능한 상황에서 failure 표시를 수행하면, user-visible status는 `restore_failed`를 유지한 채 실패 범위가 별도로 드러나야 한다.
- [ ] restore failure 후 새 session으로 폴백하는 상황에서도, 사용자는 기존 session을 복원하지 못했다는 사실을 확인할 수 있어야 한다.

## Permissions / Dependencies

- restore failure classifier와 session UI renderer가 필요하다.
- 새 session 시작 경로는 [CBW-005-start_chat_conversation_session](CBW-005-start_chat_conversation_session.md)과 연결되어야 한다.

## Observability / Analytics

- session restore failure type
- retry after restore failure
- fallback to new session count

## Related Interactions

- [CBW-005-continue_chat_conversation_session](CBW-005-continue_chat_conversation_session.md)
- [CBW-005-restore_chat_conversation_session](CBW-005-restore_chat_conversation_session.md)
- [CBW-005-show_active_conversation_session](CBW-005-show_active_conversation_session.md)
- [CBW-005-show_rebind_required_state](CBW-005-show_rebind_required_state.md)
- [CBW-005-start_chat_conversation_session](CBW-005-start_chat_conversation_session.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Contracts: [chat_session_contract.toml](../contracts/chat_session_contract.toml)
- Source line: `183`
