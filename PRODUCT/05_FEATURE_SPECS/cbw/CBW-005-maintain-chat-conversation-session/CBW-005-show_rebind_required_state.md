---
interaction_id: "CBW-005-show_rebind_required_state"
interaction_type: "display"
feature: "Maintain Chat Conversation Session"
category_key: "CBW"
feature_id: "CBW-005"
status: "드래프트"
summary: "<<AI>> 현재 맥락 기준이 바뀌어 기존 세션을 그대로 이어가기 어려운 경우 재바인딩 또는 새 세션 시작 경로를 표시한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.message_area"
menu: "-"
shortcut: "-"
---

# Show Rebind Required State

## Intent

- 현재 맥락 기준이 달라져 기존 세션을 그대로 이어가기 어렵다는 사실을 사용자에게 명확히 알린다.
- 사용자가 재바인딩, 새 세션 시작, 현재 상태 유지 중 적절한 다음 행동을 고를 수 있게 한다.

## Trigger / Entry Points

- session restore 이후 현재 맥락과 기존 세션 바인딩이 불일치한다고 판정될 때 호출된다.
- 재진입 시 복원 자체는 가능하지만 그대로 이어가면 오해를 일으킬 수 있는 상태가 감지될 때 호출된다.

## Preconditions

- 기존 session metadata와 현재 맥락 기준의 차이가 판정된 상태
- chat surface에 rebind-required state를 노출할 수 있는 상태

## Expected Outcome

- 사용자는 왜 기존 세션을 그대로 이어가기 어려운지 이해하고, 재바인딩 또는 새 세션 시작을 선택할 수 있어야 한다.
- 기존 transcript는 즉시 파기되지 않고, 사용자가 후속 경로를 결정할 때까지 안전하게 보존되어야 한다.

## State Changes

- `chat_session`의 user-visible status가 `rebind_required`로 유지된다.
- 후속 CTA로 현재 `request_context` 확인, 재바인딩, 새 session 시작 경로가 연결된다.

## User-visible Feedback

- 현재 맥락이 달라졌다는 이유와 영향 범위가 보여야 한다.
- 재바인딩, 새 세션 시작, 현재 transcript 확인 같은 후속 행동이 함께 보여야 한다.

## Edge Cases / Failure Handling

- 일부 맥락만 달라졌다면 full mismatch가 아니라 변경 범위를 요약해 보여야 한다.
- session restore failure와 rebind required는 같은 copy로 합치지 말고 원인을 구분해야 한다.
- 사용자가 즉시 새 세션 시작으로 폴백하더라도 rebind가 필요했다는 사실은 한 번은 보여야 한다.

## Acceptance Criteria

- [ ] 현재 맥락 기준이 기존 세션과 다르게 판정된 상황에서 rebind required 표시를 수행하면, 사용자는 기존 세션을 그대로 잇기 어려운 이유와 다음 행동을 이해할 수 있어야 한다.
- [ ] 기존 transcript는 여전히 볼 수 있지만 새 요청 전 재바인딩이 필요한 상황에서 rebind required 표시를 수행하면, transcript와 후속 CTA가 함께 유지되어야 한다.
- [ ] 사용자가 새 세션 시작으로 폴백하는 상황에서도, rebind가 필요했다는 사실을 확인할 수 있어야 한다.

## Permissions / Dependencies

- context binding diff 판단 로직과 session UI renderer가 필요하다.
- 재바인딩 경로는 [CBW-002-show_request_context](../CBW-002-manage-request-context/CBW-002-show_request_context.md), 새 세션 시작 경로는 [CBW-005-start_chat_conversation_session](CBW-005-start_chat_conversation_session.md)과 연결되어야 한다.

## Observability / Analytics

- rebind required exposure
- rebind vs new session choice ratio
- mismatch reason distribution

## Related Interactions

- [CBW-005-continue_chat_conversation_session](CBW-005-continue_chat_conversation_session.md)
- [CBW-005-restore_chat_conversation_session](CBW-005-restore_chat_conversation_session.md)
- [CBW-005-show_active_conversation_session](CBW-005-show_active_conversation_session.md)
- [CBW-005-show_chat_session_restore_failure](CBW-005-show_chat_session_restore_failure.md)
- [CBW-005-start_chat_conversation_session](CBW-005-start_chat_conversation_session.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Contracts: [chat_session_contract.toml](../contracts/chat_session_contract.toml)
- Source line: `184`
