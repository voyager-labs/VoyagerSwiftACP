---
interaction_id: "TCW-001-show_request_state"
interaction_type: "display"
feature: "Manage Test Requests"
category_key: "TCW"
feature_id: "TCW-001"
status: "드래프트"
summary: "테스트 request의 processing, completed, failed, cancelled 상태를 표시한다."
related_region: "test_window.chat_panel.message_area"
menu: "-"
shortcut: "-"
---

# Show Test Request State

## Intent

- request 상태를 표시한다.

## Trigger / Entry Points

- request 상태가 바뀔 때 갱신된다.

## Preconditions

- request record가 있어야 한다.

## Expected Outcome

- message area에 processing, completed, failed, cancelled 상태가 표시된다.

## State Changes

- 표시 상태가 request 상태와 동기화된다.

## User-visible Feedback

- 사용자는 request 상태를 구분할 수 있어야 한다.

## Edge Cases / Failure Handling

- 마지막 상태만 남아야 한다.

## Acceptance Criteria

- [ ] request 상태가 바뀌면, 표시도 같은 상태로 바뀌어야 한다.

## Permissions / Dependencies

- [request_lifecycle.toml](../contracts/request_lifecycle.toml)을 따른다.

## Observability / Analytics

- state transition 이벤트

## Related Interactions

- [TCW-001-submit_request](TCW-001-submit_request.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `3`
