---
interaction_id: "CBW-002-add_attachment_from_picker"
interaction_type: "command"
feature: "Manage Request Context"
category_key: "CBW"
feature_id: "CBW-002"
status: "기획 완료"
summary: "context picker를 열어 현재 요청에 포함할 파일·폴더·컬렉션 등 첨부 대상을 선택해 추가한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.chat_field"
menu: "-"
shortcut: "-"
---

# Add Attachment from Picker

## Intent

- 사용자가 명시적으로 현재 요청에 포함할 attachment를 선택할 수 있게 한다.
- 자동으로 준비된 current context(page·selection)만으로 부족한 경우 보강용 attachment를 추가한다.

## Trigger / Entry Points

- Chat Field의 context 추가 affordance를 선택할 때 호출된다.
- 현재 요청에 파일, 폴더, collection 등 attachment를 추가하고 싶을 때 호출된다.

## Preconditions

- Chat Pane과 Chat Field가 표시된 상태
- picker에서 탐색 가능한 대상 목록 또는 검색 기능이 준비된 상태

## Expected Outcome

- 사용자가 picker에서 선택한 대상이 draft request context의 added attachments 영역에 attachment 항목으로 추가되어야 한다.
- 중복 추가는 방지되거나 merge 규칙에 따라 정리되어야 한다.

## State Changes

- context picker open state가 활성화된다.
- 선택 완료 후 draft request context의 added attachments 영역이 attachment 항목 기준으로 갱신된다.

## User-visible Feedback

- picker가 열리고 선택 가능한 대상이 표시되어야 한다.
- 추가가 완료되면 current context를 건드리지 않고 added attachments의 chip이나 summary가 즉시 갱신되어야 한다.

## Edge Cases / Failure Handling

- 동일 attachment를 다시 추가하려 하면 중복 chip을 늘리지 말아야 한다.
- 지원하지 않는 대상 타입은 picker에서 비활성화하거나 선택 직후 차단해야 한다.
- 접근 권한이 없는 대상은 추가하지 않고 이유를 알려야 한다.

## Acceptance Criteria

- [ ] 사용자가 context picker에서 유효한 대상을 선택한 상황에서 추가를 수행하면, 해당 대상은 현재 요청의 draft context 안의 added attachments 영역에 attachment 항목으로 포함되어야 한다.
- [ ] 이미 포함된 대상을 다시 추가하는 상황에서 사용자가 추가를 수행하면, 중복 context 항목이 새로 생기지 않아야 한다.
- [ ] 권한이 없거나 지원하지 않는 대상을 선택한 상황에서 사용자가 추가를 수행하면, draft context는 유지되고 실패 이유가 보여야 한다.

## Permissions / Dependencies

- 탐색 가능한 context picker source가 필요하다.
- 선택 결과는 [CBW-002-show_request_context](CBW-002-show_request_context.md)에 즉시 반영되어야 한다.

## Observability / Analytics

- picker open 이벤트
- picker selection count
- duplicate add prevented count

## Related Interactions

- [CBW-002-add_inline_attachment](CBW-002-add_inline_attachment.md)
- [CBW-002-add_selection_to_context](CBW-002-add_selection_to_context.md)
- [CBW-002-capture_request_context_snapshot](CBW-002-capture_request_context_snapshot.md)
- [CBW-002-remove_request_context](CBW-002-remove_request_context.md)
- [CBW-002-show_request_context](CBW-002-show_request_context.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:160`
- Contracts: [request_context_contract.toml](../contracts/request_context_contract.toml)
- Flows: [request_context_management_flow.md](../flows/request_context_management_flow.md)
