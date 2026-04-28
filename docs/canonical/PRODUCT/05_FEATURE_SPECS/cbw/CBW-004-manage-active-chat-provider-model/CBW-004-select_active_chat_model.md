---
interaction_id: "CBW-004-select_active_chat_model"
interaction_type: "input"
feature: "Manage Active Chat Provider & Model"
category_key: "CBW"
feature_id: "CBW-004"
status: "기획 완료"
summary: "현재 대화에 적용할 모델을 선택해 다음 요청부터 사용할 활성 모델을 갱신한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.chat_field"
menu: "-"
shortcut: "-"
---

# Select Active Chat Model

## Intent

- 현재 대화에 적용할 model을 사용자가 직접 선택하게 한다.
- 선택 결과를 다음 요청부터 일관되게 반영해 active model을 갱신한다.

## Trigger / Entry Points

- Chat Field 내부의 model selector에서 선택 가능한 model 항목을 고를 때 호출된다.

## Preconditions

- model selector가 열려 있고 선택 가능한 model 항목이 존재하는 상태
- 선택 결과를 현재 chat session에 저장할 수 있는 상태

## Expected Outcome

- 선택한 model row가 현재 대화의 active model로 저장되어 결과 상태가 `model_selected`가 되어야 한다.
- 이미 실행 중인 run에는 소급 적용되지 않고 다음 request부터 반영되어야 한다.

## State Changes

- 현재 chat session의 active model 값이 새 선택으로 갱신된다.
- selector와 active model 표시 영역이 새 값으로 동기화된다.
- 선택한 model row에 연결된 provider binding이 다음 request에 사용할 값으로 함께 확정된다.

## User-visible Feedback

- 새 active model이 selector와 active model 표시 영역에 반영되어야 한다.
- Chat Field의 active model 표시에는 model 이름만 남아야 한다.

## Edge Cases / Failure Handling

- 현재 active model과 동일한 model을 다시 선택하면 no-op로 처리해야 한다.
- request 실행 중 model을 바꿔도 현재 run에는 소급 적용되면 안 된다.

## Acceptance Criteria

- [ ] 사용 가능한 다른 model이 있는 상황에서 사용자가 model 선택을 수행하면, 현재 대화의 active model이 새 값으로 갱신되어야 한다.
- [ ] request가 실행 중인 상황에서 사용자가 model 선택을 수행하면, 현재 run은 기존 model을 유지하고 다음 요청부터 새 model이 반영되어야 한다.
- [ ] 현재 active model과 동일한 model을 다시 선택하는 상황에서 사용자가 model 선택을 수행하면, active model은 바뀌지 않아야 한다.

## Permissions / Dependencies

- candidate model list와 session-level active model storage가 필요하다.
- request preparation은 최신 active model 값을 참조하고 실제 실행 가능성을 별도로 검증해야 한다.

## Observability / Analytics

- model select 이벤트
- model change success/failure
- same-model no-op count

## Related Interactions

- [CBW-004-open_chat_model_selector](CBW-004-open_chat_model_selector.md)
- [CBW-004-show_active_chat_provider_and_model](CBW-004-show_active_chat_provider_and_model.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:171`
- Contracts: [model_selection_contract.toml](../contracts/model_selection_contract.toml)
- Flows: [chat_provider_model_selection_flow.md](../flows/chat_provider_model_selection_flow.md)
