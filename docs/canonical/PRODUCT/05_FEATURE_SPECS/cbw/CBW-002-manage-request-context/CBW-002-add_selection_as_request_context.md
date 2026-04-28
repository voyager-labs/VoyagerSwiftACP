---
interaction_id: "CBW-002-add_selection_as_request_context"
interaction_type: "command"
feature: "Manage Request Context"
category_key: "CBW"
feature_id: "CBW-002"
status: "드래프트"
summary: "<<AI>> 현재 Content Pane에서 선택된 항목 집합을 현재 요청의 context로 추가한다."
related_region: "file_manager_window.content_pane.page_container"
menu: "entry_context_menu_root"
shortcut: "-"
---

# Add Selection as Request Context

## Intent

- 현재 Content Pane selection을 빠르게 현재 요청의 context로 전환한다.
- 선택 기반 작업 흐름에서 chat으로 넘어갈 때 별도 탐색 없이 context를 넘길 수 있게 한다.

## Trigger / Entry Points

- Content Pane selection에 대한 context menu 또는 quick action에서 호출된다.
- 현재 selection을 즉시 chat 요청에 포함하고 싶을 때 호출된다.

## Preconditions

- Content Pane에 하나 이상의 selectable item이 선택된 상태
- 선택한 항목을 현재 요청 context로 변환할 수 있는 상태

## Expected Outcome

- 현재 selection 집합이 하나의 draft context group 또는 동일한 logical set으로 추가되어야 한다.
- chat field 쪽 context 표시도 즉시 갱신되어야 한다.

## State Changes

- selection 기반 context group이 draft request context에 추가된다.
- 선택 source와 context group 간 연결 메타데이터가 기록될 수 있다.

## User-visible Feedback

- 선택한 항목이 context로 추가되었다는 즉각적인 확인이 보여야 한다.
- 항목 수가 많을 때는 count 중심 summary를 사용해야 한다.

## Edge Cases / Failure Handling

- 선택이 비어 있으면 no-op 또는 안내만 표시해야 한다.
- 일부 selection만 접근 가능한 경우 접근 가능한 항목만 포함하고 제외 사유를 남겨야 한다.
- selection이 매우 큰 경우 개별 chip 대신 요약 group으로 접어야 한다.

## Acceptance Criteria

- [ ] 하나 이상의 항목이 선택된 상황에서 selection을 context로 추가하면, 선택 집합이 현재 요청의 draft context에 포함되어야 한다.
- [ ] 선택이 없는 상황에서 selection을 context로 추가하면, draft context가 변하지 않아야 하고 전송되지 않아야 한다.
- [ ] 일부 선택 항목이 접근 불가한 상황에서 selection을 context로 추가하면, 접근 가능한 항목만 포함되고 제외 사유가 표시되거나 기록되어야 한다.

## Permissions / Dependencies

- selection state reader와 context group serializer가 필요하다.
- menu 진입은 `entry_context_menu_root`를 통해 가능해야 한다.

## Observability / Analytics

- selection context add 이벤트
- selection item count
- partial inclusion count

## Related Interactions

- [CBW-002-add_context_from_picker](CBW-002-add_context_from_picker.md)
- [CBW-002-add_inline_context_reference](CBW-002-add_inline_context_reference.md)
- [CBW-002-capture_request_context_snapshot](CBW-002-capture_request_context_snapshot.md)
- [CBW-002-edit_request_context](CBW-002-edit_request_context.md)
- [CBW-002-remove_request_context](CBW-002-remove_request_context.md)
- [CBW-002-show_request_context](CBW-002-show_request_context.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Contracts: [request_context_contract.toml](../contracts/request_context_contract.toml)
- Source line: `161`
