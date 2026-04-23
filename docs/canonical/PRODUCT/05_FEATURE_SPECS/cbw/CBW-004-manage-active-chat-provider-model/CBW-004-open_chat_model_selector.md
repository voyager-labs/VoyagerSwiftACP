---
interaction_id: "CBW-004-open_chat_model_selector"
interaction_type: "command"
feature: "Manage Active Chat Provider & Model"
category_key: "CBW"
feature_id: "CBW-004"
status: "기획 완료"
summary: "Chat Field 내부의 모델 선택 드롭다운을 열어 현재 대화에서 선택할 수 있는 모델 목록을 확인한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.chat_field"
menu: "-"
shortcut: "-"
---

# Open Chat Model Selector

## Intent

- 사용자가 현재 대화에서 변경 가능한 model 후보를 탐색할 수 있게 한다.
- Chat Field 내부의 model dropdown 안에서 model 이름과 현재 선택 상태를 함께 확인하게 한다.

## Trigger / Entry Points

- Chat Field 내부의 active model dropdown을 선택할 때 호출된다.

## Preconditions

- Chat Field가 표시된 상태
- 현재 대화에 대해 model selector를 열 수 있는 권한과 candidate model source가 준비된 상태

## Expected Outcome

- model selector가 열리고 현재 active model이 강조되어야 하며 상태는 `model_selector_open`으로 진입해야 한다.
- 선택 가능한 model 목록과 각 model row의 provider 정보는 model selector 안에 표시되어야 한다.
- dropdown 단계에서는 runtime 실행 가능성 대신 현재 선택 가능한 catalog 항목만 표시되어야 한다.

## State Changes

- Chat Field 내부의 model dropdown이 `model_selector_open` 상태로 전환된다.
- 각 model 항목에는 현재 catalog 기준 model label과 provider 구분 정보가 함께 계산된다.

## User-visible Feedback

- model selector가 열린 상태가 표시되어야 한다.
- 현재 선택된 model row가 selector 안에서 표시되어야 한다.
- 각 model row에는 provider 구분 정보가 표시되어야 한다.

## Edge Cases / Failure Handling

- candidate model이 하나뿐이거나 현재 선택 외에 다른 후보가 없더라도 selector는 열려야 한다.
- selector가 열려 있는 동안 candidate model 목록이 갱신되면 현재 표시 중인 목록과 선택 상태가 최신 값으로 동기화되어야 한다.
- selector 단계에서는 provider 연결 상태나 row-level blocked reason을 새로 판정해 보여주면 안 된다.
- request 실행 중 selector를 열어도 현재 run이 중단되면 안 된다.

## Acceptance Criteria

- [ ] 현재 대화에서 model 변경이 가능한 상황에서 selector 열기를 수행하면, model selector가 열리고 현재 active model이 표시되어야 한다.
- [ ] 현재 선택 외에 다른 model 후보가 없는 상황에서 selector 열기를 수행하면, selector는 열리되 현재 선택 상태와 후보 목록이 그대로 보여야 한다.
- [ ] selector가 열린 상태에서 candidate model 목록이 갱신되는 상황에서 표시를 수행하면, 현재 선택 상태와 목록이 최신 catalog 기준으로 다시 동기화되어야 한다.

## Permissions / Dependencies

- candidate model source와 selector UI surface가 필요하다.
- request preparation은 selector에서 고른 active model을 실행 직전에 별도로 검증해야 한다.

## Observability / Analytics

- model selector open 이벤트
- selector open blocked count
- open to selection conversion rate

## Related Interactions

- [CBW-004-select_active_chat_model](CBW-004-select_active_chat_model.md)
- [CBW-004-show_active_chat_provider_and_model](CBW-004-show_active_chat_provider_and_model.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:170`
- Contracts: [model_selection_contract.toml](../contracts/model_selection_contract.toml)
- Flows: [chat_provider_model_selection_flow.md](../flows/chat_provider_model_selection_flow.md)
