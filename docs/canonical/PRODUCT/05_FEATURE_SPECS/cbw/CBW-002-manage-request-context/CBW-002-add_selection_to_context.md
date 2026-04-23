---
interaction_id: "CBW-002-add_selection_to_context"
interaction_type: "command"
feature: "Manage Request Context"
category_key: "CBW"
feature_id: "CBW-002"
status: "기획 완료"
summary: "현재 Content Pane의 선택 항목을 현재 요청 컨텍스트의 선택 항목으로 갱신한다."
related_region: "file_manager_window.content_pane.page_container"
menu: "entry_context_menu_root"
shortcut: "-"
---

# Add Selection to Context

## Intent

- 현재 Content Pane selection을 빠르게 현재 요청의 current context 안의 selection 항목으로 반영한다.
- 선택 기반 작업 흐름에서 chat으로 넘어간 뒤에도 고정된 current context 안의 selection 값을 최신 상태로 갱신할 수 있게 한다.

## Trigger / Entry Points

- Content Pane selection에 대한 context menu 또는 quick action에서 호출된다.
- 현재 selection을 즉시 chat 요청에 포함하고 싶을 때 호출된다.

## Preconditions

- Content Pane에 하나 이상의 selectable item이 선택된 상태
- 선택한 항목을 현재 요청의 request context 항목으로 변환할 수 있는 상태

## Expected Outcome

- 현재 selection 집합이 고정된 current context 안의 단일 selection chip 상태에 반영되거나 교체되어야 한다.
- Chat Field 쪽 current context 표시도 즉시 갱신되어야 한다.

## State Changes

- current context 안의 selection entry가 현재 selection 기준으로 갱신된다.
- 선택 source와 current context selection entry 간 연결 메타데이터가 기록될 수 있다.

## User-visible Feedback

- 선택한 항목이 attachment chip으로 늘어나지 않고, current context 안의 단일 selection chip이 현재 선택 상태를 반영하도록 갱신되었다는 즉각적인 확인이 보여야 한다.
- selection chip은 필요 시 선택 개수나 대표 라벨을 포함할 수 있지만, 선택한 각 항목이 개별 chip으로 추가되면 안 된다.

## Edge Cases / Failure Handling

- 선택이 비어 있으면 no-op 또는 안내만 표시해야 한다.
- 일부 selection만 접근 가능한 경우 접근 가능한 항목만 포함하고 제외 사유를 남겨야 한다.
- selection이 매우 큰 경우에도 current context 안의 단일 selection chip만 갱신하고, 개별 selection item chip을 생성하면 안 된다.

## Acceptance Criteria

- [ ] 하나 이상의 항목이 선택된 상황에서 selection을 context로 추가하면, 선택 집합이 현재 요청의 current context 안의 단일 selection chip 상태로 반영되어야 한다.
- [ ] 선택이 없는 상황에서 selection을 context로 추가하면, draft request context가 변하지 않아야 하고 전송되지 않아야 한다.
- [ ] 일부 선택 항목이 접근 불가한 상황에서 selection을 context로 추가하면, 접근 가능한 항목만 current context selection에 반영되고 제외 사유가 표시되거나 기록되어야 한다.

## Permissions / Dependencies

- selection state reader와 current context serializer가 필요하다.
- menu 진입은 `entry_context_menu_root`를 통해 가능해야 한다.

## Observability / Analytics

- selection current context update 이벤트
- selection item count
- partial inclusion count

## Related Interactions

- [CBW-002-add_attachment_from_picker](CBW-002-add_attachment_from_picker.md)
- [CBW-002-add_inline_attachment](CBW-002-add_inline_attachment.md)
- [CBW-002-capture_request_context_snapshot](CBW-002-capture_request_context_snapshot.md)
- [CBW-002-remove_request_context](CBW-002-remove_request_context.md)
- [CBW-002-show_request_context](CBW-002-show_request_context.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:161`
- Contracts: [request_context_contract.toml](../contracts/request_context_contract.toml)
- Flows: [request_context_management_flow.md](../flows/request_context_management_flow.md)
