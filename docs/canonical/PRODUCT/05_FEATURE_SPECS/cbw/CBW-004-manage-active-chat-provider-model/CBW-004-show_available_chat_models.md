---
interaction_id: "CBW-004-show_available_chat_models"
interaction_type: "display"
feature: "Manage Active Chat Provider & Model"
category_key: "CBW"
feature_id: "CBW-004"
status: "드래프트"
summary: "<<AI>> 현재 연결 상태와 provider 기준으로 선택 가능한 model 목록과 비활성 사유를 표시한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.chat_menu_area"
menu: "-"
shortcut: "-"
---

# Show Available Chat Models

## Intent

- 현재 연결 상태와 provider 기준으로 어떤 model을 선택할 수 있는지 보여준다.
- 단순 목록이 아니라 비활성 이유까지 함께 제공해 사용자가 왜 못 고르는지 이해하게 한다.

## Trigger / Entry Points

- model selector가 열릴 때 표시된다.
- provider 연결 상태나 model availability가 바뀌면 갱신된다.

## Preconditions

- candidate model 목록 또는 availability metadata를 조회할 수 있는 상태

## Expected Outcome

- 사용자는 선택 가능한 model과 선택 불가 model을 구분해 볼 수 있어야 한다.
- 각 비활성 항목에는 최소한의 이유가 붙어야 한다.

## State Changes

- selector 내부 model list가 최신 availability metadata로 갱신된다.
- enabled/disabled state와 reason이 각 item에 연결된다.

## User-visible Feedback

- 사용 가능한 model은 선택 가능한 affordance로 보여야 한다.
- 선택 불가 model은 회색 처리만 하지 말고 이유 텍스트나 tooltip 등으로 설명해야 한다.

## Edge Cases / Failure Handling

- 목록 조회가 지연되면 loading state를 보여야 한다.
- provider가 바뀌거나 연결이 끊기면 이전 provider 목록이 그대로 남아 있으면 안 된다.
- 활성 model이 목록에서 제거되면 unavailable state와 함께 대체 행동이 필요하다.

## Acceptance Criteria

- [ ] model selector가 열린 상황에서 available models 표시를 수행하면, 사용 가능한 model과 선택 불가 model이 구분되어 보여야 한다.
- [ ] 일부 model이 현재 연결 상태에서 사용할 수 없는 상황에서 available models 표시를 수행하면, 각 항목별 비활성 이유가 함께 보여야 한다.
- [ ] 목록 조회가 아직 끝나지 않은 상황에서 available models 표시를 수행하면, 빈 목록 대신 loading state가 보여야 한다.

## Permissions / Dependencies

- provider별 model catalog와 connection entitlement 정보를 참조해야 한다.

## Observability / Analytics

- available model list exposure
- disabled reason distribution
- catalog load latency

## Related Interactions

- [CBW-004-open_chat_model_selector](CBW-004-open_chat_model_selector.md)
- [CBW-004-open_chat_provider_selector](CBW-004-open_chat_provider_selector.md)
- [CBW-004-select_active_chat_model](CBW-004-select_active_chat_model.md)
- [CBW-004-select_active_chat_provider](CBW-004-select_active_chat_provider.md)
- [CBW-004-show_active_chat_provider_and_model](CBW-004-show_active_chat_provider_and_model.md)
- [CBW-004-show_available_chat_providers](CBW-004-show_available_chat_providers.md)
- [CBW-004-show_unavailable_chat_model_state](CBW-004-show_unavailable_chat_model_state.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Contracts: [model_selection_contract.toml](../contracts/model_selection_contract.toml)
- Source line: `176`
