---
interaction_id: "TKY-001-show_inspector_status"
interaction_type: "display"
feature: "Manage Keyed Regions"
category_key: "TKY"
feature_id: "TKY-001"
status: "드래프트"
summary: "인스펙터 상태를 표시한다."
related_region: "test_window.inspector_pane.missing_area"
menu: "-"
shortcut: "-"
---

# Show Inspector Status

## Intent

- 인스펙터 상태를 표시한다.

## Trigger / Entry Points

- 인스펙터 상태가 바뀔 때 갱신된다.

## Preconditions

- 인스펙터가 열려 있어야 한다.

## Expected Outcome

- 상태가 표시된다.

## State Changes

- 표시 상태가 갱신된다.

## User-visible Feedback

- 사용자는 현재 상태를 볼 수 있어야 한다.

## Edge Cases / Failure Handling

- 마지막 상태만 남아야 한다.

## Acceptance Criteria

- [ ] 상태가 바뀌면, 표시도 갱신되어야 한다.

## Permissions / Dependencies

- -

## Observability / Analytics

- status render 이벤트

## Related Interactions

- -

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `2`
