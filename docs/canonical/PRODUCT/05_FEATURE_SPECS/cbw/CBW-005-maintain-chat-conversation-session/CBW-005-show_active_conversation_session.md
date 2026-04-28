---
interaction_id: "CBW-005-show_active_conversation_session"
interaction_type: "display"
feature: "Maintain Chat Conversation Session"
category_key: "CBW"
feature_id: "CBW-005"
status: "드래프트"
summary: "<<AI>> 현재 `chat_session`이 `new_session`인지 `restored_session`인지와 최소 메타정보를 chat UI에 표시한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.chat_menu_area"
menu: "-"
shortcut: "-"
---

# Show Active Conversation Session

## Intent

- 사용자가 현재 `chat_session`이 `new_session`인지 `restored_session`인지 최소한으로 이해할 수 있게 한다.
- session continuity와 request-scoped context를 혼동하지 않도록 session 상태를 별도로 보여준다.

## Trigger / Entry Points

- chat 진입, session 복원, session continue 후 상태가 바뀔 때 표시된다.

## Preconditions

- 표시할 `chat_session` metadata가 존재하거나 상태 판정 중인 상태
- chat UI에 session state indicator를 표시할 수 있는 상태

## Expected Outcome

- 사용자는 현재 대화가 `restored_session`인지 `new_session`인지, 최소한의 session 상태를 볼 수 있어야 한다.
- session 상태가 아직 판정 중이면 이전 stale indicator 대신 판정 중임을 보여주는 보조 표시가 드러나야 한다.

## State Changes

- chat menu 또는 동등한 위치의 session indicator가 `chat_session` metadata와 동기화된다.

## User-visible Feedback

- `restored_session`과 `new_session`이 구분되어 보여야 한다.
- 필요 시 turn count나 last restored marker 같은 최소 메타정보를 함께 보여줄 수 있다.

## Edge Cases / Failure Handling

- 복원 직후와 새 session 시작 직후가 시각적으로 구분되지 않으면 안 된다.
- session metadata가 아직 판정 중이면 이전 stale indicator를 유지하지 말아야 한다.
- request context가 비어 있어도 session indicator는 별도로 유지되어야 한다.

## Acceptance Criteria

- [ ] `chat_session`이 `restored_session` 또는 `new_session`으로 판정된 상황에서 session 표시를 수행하면, 사용자는 현재 대화가 새 session인지 이어진 session인지 구분할 수 있어야 한다.
- [ ] session metadata가 아직 준비되지 않은 상황에서 session 표시를 수행하면, stale한 이전 상태 대신 상태 판정 중임을 보여주는 보조 표시가 보여야 한다.
- [ ] request context가 비어 있는 상황에서도 session 표시를 수행하면, session 상태와 request context empty state가 서로 혼동되지 않아야 한다.

## Permissions / Dependencies

- active session store와 chat metadata renderer가 필요하다.

## Observability / Analytics

- session state indicator exposure
- restored vs new session distribution

## Related Interactions

- [CBW-005-continue_chat_conversation_session](CBW-005-continue_chat_conversation_session.md)
- [CBW-005-restore_chat_conversation_session](CBW-005-restore_chat_conversation_session.md)
- [CBW-005-show_chat_session_restore_failure](CBW-005-show_chat_session_restore_failure.md)
- [CBW-005-show_rebind_required_state](CBW-005-show_rebind_required_state.md)
- [CBW-005-start_chat_conversation_session](CBW-005-start_chat_conversation_session.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `182`
