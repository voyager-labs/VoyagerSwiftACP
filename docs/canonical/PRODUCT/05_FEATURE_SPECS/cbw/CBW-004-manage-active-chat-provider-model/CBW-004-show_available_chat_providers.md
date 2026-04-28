---
interaction_id: "CBW-004-show_available_chat_providers"
interaction_type: "display"
feature: "Manage Active Chat Provider & Model"
category_key: "CBW"
feature_id: "CBW-004"
status: "드래프트"
summary: "<<AI>> 현재 대화에서 선택 가능한 provider 목록과 각 provider의 연결 가능 여부, 비활성 사유를 표시한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.chat_menu_area"
menu: "-"
shortcut: "-"
---

# Show Available Chat Providers

## Intent

- 현재 대화에서 어떤 provider를 선택할 수 있는지 보여준다.
- 단순 목록이 아니라 각 provider의 연결 가능 여부와 전환 불가 이유를 함께 제공한다.

## Trigger / Entry Points

- provider selector가 열릴 때 표시된다.
- provider 연결 상태나 entitlement가 바뀌면 갱신된다.

## Preconditions

- candidate provider 목록 또는 availability metadata를 조회할 수 있는 상태

## Expected Outcome

- 사용자는 바로 전환 가능한 provider와 연결이 필요하거나 비활성인 provider를 구분해 볼 수 있어야 한다.
- 각 비활성 항목에는 최소한의 이유가 붙어야 한다.

## State Changes

- selector 내부 provider list가 최신 availability metadata로 갱신된다.
- enabled/disabled state와 reason이 각 item에 연결된다.

## User-visible Feedback

- 사용 가능한 provider는 선택 가능한 affordance로 보여야 한다.
- 연결 필요 또는 선택 불가 provider는 상태 문구나 tooltip 등으로 이유가 설명되어야 한다.

## Edge Cases / Failure Handling

- 목록 조회가 지연되면 loading state를 보여야 한다.
- 현재 active provider가 방금 무효가 된 경우 unavailable state와 대체 경로가 같이 보여야 한다.
- 연결 상태가 바뀌면 이전 stale provider 목록이 그대로 남아 있으면 안 된다.

## Acceptance Criteria

- [ ] provider selector가 열린 상황에서 available providers 표시를 수행하면, 전환 가능한 provider와 전환 불가 provider가 구분되어 보여야 한다.
- [ ] 일부 provider가 현재 연결 상태에서 사용할 수 없는 상황에서 available providers 표시를 수행하면, 각 항목별 비활성 이유가 함께 보여야 한다.
- [ ] 목록 조회가 아직 끝나지 않은 상황에서 available providers 표시를 수행하면, 빈 목록 대신 loading state가 보여야 한다.

## Permissions / Dependencies

- provider별 연결 상태, entitlement, 기본 전환 정책을 참조해야 한다.
- 상태 정확도는 `SET-007` 연결 상태와 동기화되어야 한다.

## Observability / Analytics

- available provider list exposure
- disabled reason distribution
- catalog load latency

## Related Interactions

- [CBW-004-open_chat_model_selector](CBW-004-open_chat_model_selector.md)
- [CBW-004-open_chat_provider_selector](CBW-004-open_chat_provider_selector.md)
- [CBW-004-select_active_chat_model](CBW-004-select_active_chat_model.md)
- [CBW-004-select_active_chat_provider](CBW-004-select_active_chat_provider.md)
- [CBW-004-show_active_chat_provider_and_model](CBW-004-show_active_chat_provider_and_model.md)
- [CBW-004-show_available_chat_models](CBW-004-show_available_chat_models.md)
- [CBW-004-show_unavailable_chat_model_state](CBW-004-show_unavailable_chat_model_state.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Contracts: [provider_selection_contract.toml](../contracts/provider_selection_contract.toml)
- Source line: `173`
