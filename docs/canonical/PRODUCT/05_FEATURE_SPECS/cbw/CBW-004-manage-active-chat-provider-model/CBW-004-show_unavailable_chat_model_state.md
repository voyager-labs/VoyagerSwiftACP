---
interaction_id: "CBW-004-show_unavailable_chat_model_state"
interaction_type: "display"
feature: "Manage Active Chat Provider & Model"
category_key: "CBW"
feature_id: "CBW-004"
status: "드래프트"
summary: "<<AI>> model 변경이 불가하거나 현재 선택이 더 이상 유효하지 않을 때 이유와 다음 행동을 표시한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.chat_menu_area"
menu: "-"
shortcut: "-"
---

# Show Unavailable Chat Model State

## Intent

- 현재 선택 model 또는 원하는 model이 사용할 수 없는 상태를 명확하게 보여준다.
- 실패 이유와 다음 행동을 함께 제시해 막다른길 UX를 줄인다.

## Trigger / Entry Points

- active model이 무효가 되었거나 특정 model 선택이 차단될 때 호출된다.
- selector 또는 active model display가 unavailable state를 렌더링해야 할 때 표시된다.

## Preconditions

- model unavailable reason이 분류된 상태
- chat menu 영역이 관련 warning을 표시할 수 있는 상태

## Expected Outcome

- 사용자는 현재 왜 model을 쓸 수 없는지와 무엇을 해야 하는지 이해할 수 있어야 한다.
- unavailable state는 normal active state와 명확히 구분되어야 한다.

## State Changes

- active model display 또는 selector item이 unavailable presentation으로 전환된다.
- 후속 CTA(연결 수정, 다른 model 선택 등)가 연결된다.

## User-visible Feedback

- reason text, disabled affordance, 가능한 다음 행동이 함께 보여야 한다.
- 전체 model이 unavailable이면 단일 CTA보다 상태 요약을 우선해야 한다.

## Edge Cases / Failure Handling

- 연결 끊김, entitlement 부족, model deprecated, provider mismatch를 최소한 구분해 보여야 한다.
- active model이 갑자기 unavailable이 되어도 즉시 다른 model로 silent fallback하지 않아야 한다.
- selector가 닫힌 상태에서도 active display 영역에서 문제를 인지할 수 있어야 한다.

## Acceptance Criteria

- [ ] 현재 active model이 더 이상 유효하지 않은 상황에서 unavailable state 표시를 수행하면, 사용자는 정상 active state와 구분되는 문제 상태를 봐야 한다.
- [ ] model 변경이 차단되는 상황에서 unavailable state 표시를 수행하면, 차단 이유와 가능한 다음 행동이 함께 보여야 한다.
- [ ] 연결 불일치로 모든 model이 unavailable인 상황에서 unavailable state 표시를 수행하면, 단순 무반응 대신 전체 unavailable 상태가 설명되어야 한다.

## Permissions / Dependencies

- availability reason classifier와 chat model display renderer에 의존한다.
- 연결 관련 원인은 `SET-007`, 실행 실패 표시는 [CBW-003-show_request_resolution_failure](../CBW-003-resolve-contextual-chat-requests/CBW-003-show_request_resolution_failure.md)와 연계될 수 있다.

## Observability / Analytics

- unavailable state exposure
- reason code distribution
- follow-up CTA click through

## Related Interactions

- [CBW-004-open_chat_model_selector](CBW-004-open_chat_model_selector.md)
- [CBW-004-open_chat_provider_selector](CBW-004-open_chat_provider_selector.md)
- [CBW-004-select_active_chat_model](CBW-004-select_active_chat_model.md)
- [CBW-004-select_active_chat_provider](CBW-004-select_active_chat_provider.md)
- [CBW-004-show_active_chat_provider_and_model](CBW-004-show_active_chat_provider_and_model.md)
- [CBW-004-show_available_chat_models](CBW-004-show_available_chat_models.md)
- [CBW-004-show_available_chat_providers](CBW-004-show_available_chat_providers.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Contracts: [model_selection_contract.toml](../contracts/model_selection_contract.toml)
- Source line: `178`
