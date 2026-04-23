---
interaction_id: "CBW-004-show_active_chat_provider_and_model"
interaction_type: "display"
feature: "Manage Active Chat Provider & Model"
category_key: "CBW"
feature_id: "CBW-004"
status: "기획 완료"
summary: "Chat Field 내부의 모델 선택 드롭다운에 현재 대화에 적용 중인 활성 모델 이름을 표시한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.chat_field"
menu: "-"
shortcut: "-"
---

# Show Active Chat Provider & Model

## Intent

- 현재 대화에 어떤 active model이 적용되는지 항상 식별 가능하게 한다.
- 사용자가 다음 request에 적용될 model을 Chat Field 내부의 model dropdown에서 이해하게 한다.

## Trigger / Entry Points

- chat 진입, session 복원, active model 변경, model row의 provider 연결 상태 변경 시 갱신된다.

## Preconditions

- Chat Field가 표시 가능한 상태
- 현재 대화의 active model state와 current model catalog를 조회할 수 있는 상태

## Expected Outcome

- Chat Field 내부의 model dropdown에는 현재 대화의 active model 이름이 표시되어야 한다.
- active model이 이미 있으면 표시 결과는 `model_selected` 상태로 읽혀야 한다.
- active model이 비어 있고 catalog에 model row가 있으면 첫 번째 row가 active model로 자동 선택되어 표시 결과는 `model_selected` 상태로 읽혀야 한다.
- 저장된 active model을 현재 catalog에서 해석할 수 없고 catalog에 model row가 있으면 첫 번째 row가 active model로 자동 선택되어 표시 결과는 `model_selected` 상태로 읽혀야 한다.

## State Changes

- Chat Field 내부 model dropdown의 표시 정보가 현재 active model 이름 기준으로 동기화된다.
- active model이 비어 있으면 현재 catalog의 첫 번째 model row가 active model로 저장된다.
- 저장된 active model을 현재 catalog에서 해석할 수 없고 catalog에 model row가 있으면 현재 catalog의 첫 번째 model row가 active model로 저장된다.

## User-visible Feedback

- 현재 active model이 Chat Field 내부의 model dropdown에서 식별되어야 한다.
- provider는 Chat Field가 아니라 model catalog list에서만 후보 구분 정보로 표시되어야 한다.

## Edge Cases / Failure Handling

- 현재 active model이 비어 있고 catalog에 model row가 있으면 빈 상태를 유지하지 말고 첫 번째 row를 active model로 자동 선택해야 한다.
- 저장된 active model을 현재 catalog에서 찾을 수 없고 catalog에 model row가 있으면 첫 번째 row를 active model로 자동 선택해야 한다.
- request 실행 중 다음 request에 적용될 model 변경이 예약된 경우 현재 실행 기준과 다음 실행 기준이 혼동되지 않아야 한다.

## Acceptance Criteria

- [ ] 현재 대화에 active model이 있는 상황에서 표시를 수행하면, 사용자는 Chat Field 안에서 해당 model 이름을 확인해야 한다.
- [ ] 현재 대화의 active model이 비어 있고 catalog에 model row가 있는 상황에서 표시를 수행하면, 첫 번째 model row가 active model로 자동 선택되어야 한다.
- [ ] 저장된 active model을 현재 catalog에서 해석할 수 없고 catalog에 model row가 있는 상황에서 표시를 수행하면, 첫 번째 model row가 active model로 자동 선택되어야 한다.

## Permissions / Dependencies

- `SET-007` 연결 상태와 현재 대화의 active model state를 참조해야 한다.

## Observability / Analytics

- active model 정보 노출
- missing model state rate
- displayed model vs executed model mismatch count

## Related Interactions

- [CBW-004-open_chat_model_selector](CBW-004-open_chat_model_selector.md)
- [CBW-004-select_active_chat_model](CBW-004-select_active_chat_model.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:169`
- Contracts: [model_selection_contract.toml](../contracts/model_selection_contract.toml)
- Flows: [chat_provider_model_selection_flow.md](../flows/chat_provider_model_selection_flow.md)
