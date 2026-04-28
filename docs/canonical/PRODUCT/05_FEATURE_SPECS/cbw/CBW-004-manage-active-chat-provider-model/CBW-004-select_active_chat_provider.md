---
interaction_id: "CBW-004-select_active_chat_provider"
interaction_type: "input"
feature: "Manage Active Chat Provider & Model"
category_key: "CBW"
feature_id: "CBW-004"
status: "드래프트"
summary: "<<AI>> 현재 대화에 적용할 provider를 선택하고 이후 요청부터 반영되도록 active provider 상태를 갱신한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.chat_menu_area"
menu: "-"
shortcut: "-"
---

# Select Active Chat Provider

## Intent

- 현재 대화에 적용할 provider를 사용자가 직접 선택하게 한다.
- 선택 결과를 이후 요청부터 일관되게 반영해 active provider state를 갱신한다.

## Trigger / Entry Points

- provider selector에서 특정 provider item을 선택할 때 호출된다.

## Preconditions

- provider selector가 열려 있고 선택 가능한 provider 항목이 존재하는 상태
- 선택 결과를 현재 `chat_session`에 연결할 수 있는 상태

## Expected Outcome

- 선택한 provider가 현재 대화의 active provider로 저장되어야 한다.
- 이미 실행 중인 run에는 소급 적용되지 않고 다음 request부터 반영되어야 한다.

## State Changes

- current `chat_session`의 active provider 값이 갱신된다.
- selector와 active provider/model 표시 영역이 새 값으로 동기화된다.
- 새 provider 기준의 model availability가 다시 계산된다.

## User-visible Feedback

- 사용자는 어떤 provider가 새 active provider가 되었는지 즉시 확인할 수 있어야 한다.
- in-flight request가 있는 경우 새 provider가 다음 요청부터 적용된다는 점이 혼동 없이 전달되어야 한다.

## Edge Cases / Failure Handling

- 같은 provider를 다시 선택하면 no-op로 처리해야 한다.
- 선택 직전에 연결 상태가 무효가 되었으면 갱신하지 말고 연결 필요 상태를 보여야 한다.
- provider가 바뀌면서 기존 active model이 더 이상 유효하지 않으면 model 재선택 필요 상태를 함께 표시해야 한다.

## Acceptance Criteria

- [ ] 사용 가능한 다른 provider가 있는 상황에서 사용자가 provider 선택을 수행하면, 현재 대화의 active provider가 새 값으로 갱신되어야 한다.
- [ ] request가 실행 중인 상황에서 사용자가 provider 선택을 수행하면, 현재 run은 기존 provider를 유지하고 다음 요청부터 새 provider가 반영되어야 한다.
- [ ] 선택한 provider에서 기존 active model이 유효하지 않은 상황에서 사용자가 provider 선택을 수행하면, active provider는 바뀌되 model 재선택 필요 상태가 함께 드러나야 한다.

## Permissions / Dependencies

- candidate provider availability와 session-level active provider storage가 필요하다.
- payload build는 최신 active provider 값을 참조해야 한다.

## Observability / Analytics

- provider select 이벤트
- provider change success/failure
- same-provider no-op count

## Related Interactions

- [CBW-004-open_chat_model_selector](CBW-004-open_chat_model_selector.md)
- [CBW-004-open_chat_provider_selector](CBW-004-open_chat_provider_selector.md)
- [CBW-004-select_active_chat_model](CBW-004-select_active_chat_model.md)
- [CBW-004-show_active_chat_provider_and_model](CBW-004-show_active_chat_provider_and_model.md)
- [CBW-004-show_available_chat_models](CBW-004-show_available_chat_models.md)
- [CBW-004-show_available_chat_providers](CBW-004-show_available_chat_providers.md)
- [CBW-004-show_unavailable_chat_model_state](CBW-004-show_unavailable_chat_model_state.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Contracts: [provider_selection_contract.toml](../contracts/provider_selection_contract.toml), [model_selection_contract.toml](../contracts/model_selection_contract.toml)
- Source line: `174`
