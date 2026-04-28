---
interaction_id: "CBW-002-show_request_context"
interaction_type: "display"
feature: "Manage Request Context"
category_key: "CBW"
feature_id: "CBW-002"
status: "기획 완료"
summary: "현재 요청의 현재 맥락(페이지·선택 항목)과 명시적으로 추가한 첨부 대상을 Chat Field 주변에서 분리해 표시한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.chat_field"
menu: "-"
shortcut: "-"
---

# Show Request Context

## Intent

- 사용자가 제출 전에 현재 요청의 request context 안에서 자동으로 준비된 current context와 request context 영역에 별도로 표시되는 attachment를 구분해 이해할 수 있게 한다.
- 현재 요청에 한정된 request context와 대화의 연속성을 나타내는 chat session 상태를 시각적으로 구분한다.

## Trigger / Entry Points

- chat 진입 직후 draft context가 준비될 때 표시된다.
- request context 항목이 추가, 제거, 교체되거나 snapshot 구성이 바뀔 때 다시 렌더링된다.

## Preconditions

- Chat Field가 표시된 상태
- 현재 요청에 대한 request context 상태를 조회할 수 있는 상태

## Expected Outcome

- 사용자는 제출 전에 현재 요청의 request context를 current context, added attachments, request message 안의 inline attachment token 표현 기준으로 이해할 수 있어야 한다.
- 현재 요청의 request context 항목이 비어 있는 경우에는 request context 영역에 current context나 attachment item이 렌더링되지 않아야 한다.

## State Changes

- request context 상태가 고정된 current context group과 별도 added attachments group 형태의 UI로 반영된다.
- inline attachment는 request message token rendering으로만 표현되고 added attachments group에는 중복 렌더링되지 않는다.
- request context 항목이 변경되어도 표시 순서와 grouping 규칙이 일관되게 유지된다.

## User-visible Feedback

- 현재 page와 selection은 attachment와 다른 affordance를 쓰는 고정된 current context group 안에서 보여야 한다.
- current selection은 current context group 안의 단일 selection chip으로 표시되어야 하며, 선택한 각 item이 개별 chip으로 나열되면 안 된다.
- 사용자가 명시적으로 추가한 attachment는 separate group의 chip 또는 summary로 보여야 한다.
- Chat Field에 인라인으로 삽입된 attachment는 입력 텍스트 안의 token으로만 표시되고 added attachments group에는 다시 나타나지 않아야 한다.
- `empty_context`에서는 별도 empty chip, placeholder row, badge를 렌더링하지 않고 context 추가 affordance만 유지해야 한다.
- current context 또는 added attachments 항목이 표시 영역 너비를 넘으면, request context 영역은 줄바꿈이나 접기 대신 가로 스크롤로 overflow를 처리해야 한다.

## Edge Cases / Failure Handling

- selection 항목 수가 많아도 current selection은 단일 chip 상태로 유지하되, request context 영역의 가로 스크롤 안에서 탐색 가능해야 한다.
- 삭제되었거나 접근 불가한 attachment 또는 기타 explicit entry는 broken state로 구분해 보여야 한다.
- 현재 요청의 request context가 비어 있어도 error로 처리하지 말고, context item이 하나도 렌더링되지 않는 상태를 유지해야 한다.

## Acceptance Criteria

- [ ] draft request context가 존재하는 상황에서 context 표시를 수행하면, 사용자는 current context와 added attachments가 분리된 형태로 포함 대상과 범위를 확인할 수 있어야 하며 inline attachment는 입력 텍스트 token으로만 드러나야 한다.
- [ ] 하나 이상의 selection item이 현재 request context에 반영된 상황에서 context 표시를 수행하면, current selection은 단일 chip으로 보여야 하며 개별 selection item chip이 추가로 렌더링되면 안 된다.
- [ ] 현재 요청의 request context가 비어 있는 상황에서 context 표시를 수행하면, request context 영역에는 current context나 attachment item이 렌더링되지 않아야 하며 chat 입력과 submit은 막히지 않아야 한다.
- [ ] 현재 요청의 request context 일부가 더 이상 유효하지 않은 상황에서 context 표시를 수행하면, 깨진 attachment 또는 explicit entry가 일반 current context 항목과 구분되어 보여야 한다.
- [ ] current context 또는 added attachments 항목 수가 많아 표시 영역을 넘는 상황에서 context 표시를 수행하면, request context 영역은 접기 대신 가로 스크롤로 overflow를 처리해야 한다.

## Permissions / Dependencies

- draft request context store, current context renderer, attachment chip renderer에 의존한다.
- snapshot 고정 이후의 immutable request context 표현은 [CBW-002-capture_request_context_snapshot](CBW-002-capture_request_context_snapshot.md)과 연계되어야 하며, 이때 상태는 `request_context_locked`로 해석되어야 한다.

## Observability / Analytics

- current context item count
- added attachment count
- `empty_context` rate
- `broken_reference` count

## Related Interactions

- [CBW-002-add_attachment_from_picker](CBW-002-add_attachment_from_picker.md)
- [CBW-002-add_inline_attachment](CBW-002-add_inline_attachment.md)
- [CBW-002-add_selection_to_context](CBW-002-add_selection_to_context.md)
- [CBW-002-capture_request_context_snapshot](CBW-002-capture_request_context_snapshot.md)
- [CBW-002-remove_request_context](CBW-002-remove_request_context.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:159`
- Contracts: [request_context_contract.toml](../contracts/request_context_contract.toml)
- Flows: [contextual_chat_request_flow.md](../flows/contextual_chat_request_flow.md), [request_context_management_flow.md](../flows/request_context_management_flow.md)
