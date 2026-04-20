---
interaction_id: "TCW-001-submit_request"
interaction_type: "command"
feature: "Manage Test Requests"
category_key: "TCW"
feature_id: "TCW-001"
status: "드래프트"
summary: "테스트 request를 생성하고 processing 상태로 전환한다."
related_region: "test_window.chat_panel.chat_field"
menu: "-"
shortcut: "⌘↩"
---

# Submit Test Request

## Intent

- test request를 생성한다.

## Trigger / Entry Points

- Chat Field에서 submit한다.

## Preconditions

- request를 만들 수 있는 상태여야 한다.

## Expected Outcome

- request가 생성되고 processing 상태가 된다.

## State Changes

- request가 processing 상태로 전환된다.

## User-visible Feedback

- processing indicator가 표시된다.

## Edge Cases / Failure Handling

- 빈 입력이면 생성하지 않는다.

## Acceptance Criteria

- [ ] 사용자가 submit하면, request가 생성되고 processing 상태가 되어야 한다.

## Permissions / Dependencies

- [request_lifecycle.toml](../contracts/request_lifecycle.toml)을 따른다.

## Observability / Analytics

- submit 이벤트

## Related Interactions

- [TCW-001-show_request_state](TCW-001-show_request_state.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `2`
