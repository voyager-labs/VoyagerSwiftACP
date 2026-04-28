---
interaction_id: "CBW-002-edit_request_context"
interaction_type: "command"
feature: "Manage Request Context"
category_key: "CBW"
feature_id: "CBW-002"
status: "드래프트"
summary: "<<AI>> 현재 요청에 포함된 context 항목의 범위·대상·snapshot 구성을 다른 값으로 교체한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.chat_field"
menu: "-"
shortcut: "-"
---

# Edit Request Context

## Intent

- 기존 draft context 항목의 대상 또는 범위를 다른 값으로 교체할 수 있게 한다.
- remove 후 add를 강제하지 않고 수정 흐름을 제공해 사용자의 조정 비용을 줄인다.

## Trigger / Entry Points

- 기존 context 항목의 edit affordance나 동등한 수정 경로를 선택할 때 호출된다.

## Preconditions

- 수정 대상 context 항목이 draft request context에 존재하는 상태
- 수정 가능한 draft 상태이며 snapshot 고정 전이거나 새 draft를 생성할 수 있는 상태

## Expected Outcome

- 대상 context 항목이 새 대상 또는 새 범위로 교체되어야 한다.
- 교체 후 중복 항목 정리 규칙이 일관되게 적용되어야 한다.

## State Changes

- 기존 context 항목 metadata가 새 값으로 갱신되거나 교체된다.
- context summary와 관련 preview가 새 값 기준으로 갱신된다.

## User-visible Feedback

- 수정 완료 후 새 context 라벨과 범위가 즉시 보여야 한다.
- 수정이 불가능하면 차단 이유와 대안 행동을 안내해야 한다.

## Edge Cases / Failure Handling

- 새로 선택한 값이 기존 다른 context와 중복되면 merge하거나 중복 생성을 막아야 한다.
- 이미 snapshot이 고정된 요청을 수정하려 하면 원본을 바꾸지 말고 새 draft로 유도해야 한다.
- 수정 중 대상이 사라지면 저장하지 않고 이전 상태를 유지해야 한다.

## Acceptance Criteria

- [ ] draft request에 수정 가능한 context 항목이 있는 상황에서 수정을 수행하면, 해당 항목은 새 대상 또는 새 범위로 교체되어야 한다.
- [ ] 교체 대상이 다른 기존 context와 중복되는 상황에서 수정을 수행하면, 중복 context가 별도로 늘어나지 않아야 한다.
- [ ] snapshot 고정 이후의 request를 수정하려는 상황에서 수정을 수행하면, 원본 request snapshot은 유지되고 수정 불가 정책이 적용되어야 한다.

## Permissions / Dependencies

- picker 또는 reference selector 재사용이 필요하다.
- 중복 merge 규칙은 add/remove 흐름과 동일해야 한다.

## Observability / Analytics

- context edit 이벤트
- edit to duplicate prevented count
- edit blocked by locked snapshot count

## Related Interactions

- [CBW-002-add_context_from_picker](CBW-002-add_context_from_picker.md)
- [CBW-002-add_inline_context_reference](CBW-002-add_inline_context_reference.md)
- [CBW-002-add_selection_as_request_context](CBW-002-add_selection_as_request_context.md)
- [CBW-002-capture_request_context_snapshot](CBW-002-capture_request_context_snapshot.md)
- [CBW-002-remove_request_context](CBW-002-remove_request_context.md)
- [CBW-002-show_request_context](CBW-002-show_request_context.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Contracts: [request_context_contract.toml](../contracts/request_context_contract.toml)
- Source line: `164`
