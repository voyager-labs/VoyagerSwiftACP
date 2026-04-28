---
interaction_id: "CBW-002-remove_request_context"
interaction_type: "command"
feature: "Manage Request Context"
category_key: "CBW"
feature_id: "CBW-002"
status: "기획 완료"
summary: "현재 요청 컨텍스트에 포함된 특정 항목을 제거해 이후 요청 실행 입력에서 제외한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.chat_field"
menu: "-"
shortcut: "-"
---

# Remove Request Context

## Intent

- draft request에서 불필요하거나 잘못 붙은 explicit attachment 항목을 제거할 수 있게 한다.
- 사용자가 전송 전 명시적으로 추가한 attachment 범위를 빠르게 정제할 수 있게 한다.

## Trigger / Entry Points

- removable attachment chip의 remove affordance를 누르거나 동일한 remove action을 호출할 때 실행된다.

## Preconditions

- 제거 대상 explicit attachment 항목이 draft request context에 존재하는 상태
- 해당 request가 아직 snapshot 고정 전이거나 수정 가능한 draft 상태

## Expected Outcome

- 지정한 explicit attachment 항목이 draft request context에서 제거되어야 한다.
- 제거 이후 request context summary와 전송 대상 실행 입력 preview가 즉시 갱신되어야 한다.

## State Changes

- draft request context의 added attachments list에서 대상 항목이 제거된다.
- 남은 request context 항목 수와 grouping 정보가 다시 계산된다.

## User-visible Feedback

- 제거 직후 attachment chip 또는 summary가 사라져야 한다.
- current context seed가 남아 있으면 고정된 current context는 유지되고, 아무 seed도 남지 않았을 때는 request context 영역에 별도 empty item을 렌더링하지 않아야 한다.

## Edge Cases / Failure Handling

- 존재하지 않는 explicit attachment id 제거는 no-op로 처리해야 한다.
- 이미 snapshot이 고정된 request에는 직접 제거를 허용하지 않거나 새 draft로 분기해야 한다.
- current context 안의 page·selection 항목은 이 인터랙션으로 제거하지 않아야 한다.
- 동일 항목을 빠르게 반복 제거해도 상태가 꼬이지 않아야 한다.

## Acceptance Criteria

- [ ] draft request에 포함된 explicit attachment 항목이 있는 상황에서 제거를 수행하면, 해당 항목은 현재 요청의 draft context에서 제외되어야 한다.
- [ ] 마지막 explicit attachment 항목을 제거하고 current context seed도 없는 상황에서 제거를 수행하면, request context는 empty state로 전환되어야 한다.
- [ ] 이미 snapshot이 고정된 요청에 대해 제거를 수행하는 상황이면, 원본 request snapshot은 바뀌지 않아야 한다.

## Permissions / Dependencies

- draft context editor가 필요하다.
- snapshot 고정 이후 수정 정책은 [CBW-002-capture_request_context_snapshot](CBW-002-capture_request_context_snapshot.md)과 호환되어야 하며, `request_context_locked` 상태에서는 직접 수정되지 않아야 한다.

## Observability / Analytics

- explicit attachment remove 이벤트
- `empty_context` after remove rate
- remove blocked by locked snapshot count

## Related Interactions

- [CBW-002-add_attachment_from_picker](CBW-002-add_attachment_from_picker.md)
- [CBW-002-add_inline_attachment](CBW-002-add_inline_attachment.md)
- [CBW-002-add_selection_to_context](CBW-002-add_selection_to_context.md)
- [CBW-002-capture_request_context_snapshot](CBW-002-capture_request_context_snapshot.md)
- [CBW-002-show_request_context](CBW-002-show_request_context.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:163`
- Contracts: [request_context_contract.toml](../contracts/request_context_contract.toml)
- Flows: [request_context_management_flow.md](../flows/request_context_management_flow.md)
