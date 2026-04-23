---
interaction_id: "CBW-004-open_chat_provider_selector"
interaction_type: "command"
feature: "Manage Active Chat Provider & Model"
category_key: "CBW"
feature_id: "CBW-004"
status: "드래프트"
summary: "<<AI>> 현재 대화에서 전환 가능한 provider 목록과 연결 상태를 확인할 수 있는 selector를 연다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.chat_menu_area"
menu: "-"
shortcut: "-"
---

# Open Chat Provider Selector

## Intent

- 사용자가 현재 대화에서 provider 변경 가능 여부와 후보 목록을 빠르게 탐색할 수 있게 한다.
- 현재 active provider/model 표시 영역에서 provider 전환 UI로 바로 이어지게 한다.

## Trigger / Entry Points

- provider 표시 영역 또는 동등한 selector affordance를 클릭할 때 호출된다.

## Preconditions

- chat menu 영역이 표시된 상태
- 현재 대화에 대해 provider 선택 UI를 열 수 있는 권한과 surface가 준비된 상태

## Expected Outcome

- provider selector가 열리고 현재 active provider가 강조되어야 한다.
- 선택 가능한 provider와 연결이 필요하거나 비활성인 provider가 함께 표시될 준비 상태가 되어야 한다.

## State Changes

- chat provider selector open state가 활성화된다.
- 현재 active provider와 candidate provider list loading state가 연결된다.

## User-visible Feedback

- 사용자는 selector가 열렸음을 즉시 인지할 수 있어야 한다.
- 진입은 가능하지만 현재 전환할 수 없는 provider가 있다면 무반응 대신 disabled reason이 보여야 한다.

## Edge Cases / Failure Handling

- 현재 연결된 다른 provider가 없더라도 selector open은 가능하되 전환 불가 이유를 보여야 한다.
- 연결 상태 조회가 지연되면 selector 안에서 loading state를 유지해야 한다.
- 요청 실행 중일 때 selector를 열어도 현재 run이 중단되면 안 된다.

## Acceptance Criteria

- [ ] 현재 대화에서 provider 변경이 가능한 상황에서 selector 열기를 수행하면, provider selector가 열리고 현재 active provider가 표시되어야 한다.
- [ ] 연결된 다른 provider가 없는 상황에서 selector 열기를 수행하면, 빈 목록 대신 전환 불가 이유가 보여야 한다.
- [ ] request가 실행 중인 상황에서 selector 열기를 수행하면, 현재 run은 유지된 채 provider 전환 UI만 열려야 한다.

## Permissions / Dependencies

- candidate provider source와 selector UI surface가 필요하다.
- selector에서 표시할 목록은 [CBW-004-show_available_chat_providers](CBW-004-show_available_chat_providers.md)와 연계된다.

## Observability / Analytics

- provider selector open 이벤트
- selector open blocked count
- open to selection conversion rate

## Related Interactions

- [CBW-004-open_chat_model_selector](CBW-004-open_chat_model_selector.md)
- [CBW-004-select_active_chat_model](CBW-004-select_active_chat_model.md)
- [CBW-004-select_active_chat_provider](CBW-004-select_active_chat_provider.md)
- [CBW-004-show_active_chat_provider_and_model](CBW-004-show_active_chat_provider_and_model.md)
- [CBW-004-show_available_chat_models](CBW-004-show_available_chat_models.md)
- [CBW-004-show_available_chat_providers](CBW-004-show_available_chat_providers.md)
- [CBW-004-show_unavailable_chat_model_state](CBW-004-show_unavailable_chat_model_state.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Contracts: [provider_selection_contract.toml](../contracts/provider_selection_contract.toml)
- Source line: `172`
