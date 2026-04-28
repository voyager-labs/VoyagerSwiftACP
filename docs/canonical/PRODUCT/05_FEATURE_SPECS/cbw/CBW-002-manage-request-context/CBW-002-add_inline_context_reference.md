---
interaction_id: "CBW-002-add_inline_context_reference"
interaction_type: "input"
feature: "Manage Request Context"
category_key: "CBW"
feature_id: "CBW-002"
status: "드래프트"
summary: "<<AI>> Chat Field에서 인라인 참조 입력으로 현재 요청의 context 대상을 검색·삽입한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.chat_field"
menu: "-"
shortcut: "-"
---

# Add Inline Context Reference

## Intent

- 사용자가 입력 중인 문장 흐름을 끊지 않고 인라인으로 context 대상을 참조할 수 있게 한다.
- 명시적 참조와 draft request context를 동기화해 텍스트와 실제 context 대상이 어긋나지 않게 한다.

## Trigger / Entry Points

- Chat Field에서 인라인 참조 트리거를 입력할 때 호출된다.
- 사용자가 검색 결과에서 특정 참조 대상을 선택해 삽입할 때 완료된다.

## Preconditions

- Chat Field에 커서가 있고 입력 가능한 상태
- 인라인 참조 대상 검색 인덱스 또는 autocomplete source가 준비된 상태

## Expected Outcome

- 선택한 참조 대상이 입력 텍스트와 draft request context 양쪽에 일관되게 반영되어야 한다.
- 사용자는 삽입된 참조가 실제 어떤 대상인지 쉽게 확인할 수 있어야 한다.

## State Changes

- 입력값에 인라인 reference token 또는 동등한 표현이 삽입된다.
- 해당 reference가 draft request context에도 등록된다.

## User-visible Feedback

- autocomplete 목록과 선택 결과가 즉시 보여야 한다.
- 삽입 후 reference token이 일반 텍스트와 시각적으로 구분되어야 한다.

## Edge Cases / Failure Handling

- 동명이인이 많은 경우 경로나 타입 등으로 구분 가능한 후보를 보여야 한다.
- 삽입 후 대상이 삭제되면 broken reference 상태로 전환해야 한다.
- 완성되지 않은 reference token만 남은 경우 submit 전에 유효성 검사를 해야 한다.

## Acceptance Criteria

- [ ] 사용자가 Chat Field에서 인라인 참조를 선택한 상황에서 삽입을 완료하면, 해당 대상은 입력 텍스트와 draft request context에 함께 반영되어야 한다.
- [ ] 동명이인 후보가 여러 개인 상황에서 사용자가 인라인 참조를 시도하면, 식별 가능한 후보 목록이 먼저 제시되어야 한다.
- [ ] 미완성 또는 깨진 reference가 남아 있는 상황에서 사용자가 요청을 전송하면, 전송 전 보정 또는 실패 안내가 이뤄져야 한다.

## Permissions / Dependencies

- autocomplete source와 reference token renderer가 필요하다.
- broken reference 처리 규칙은 [CBW-002-show_request_context](CBW-002-show_request_context.md)와 일치해야 한다.

## Observability / Analytics

- inline reference trigger count
- reference insertion success/failure
- ambiguous match rate

## Related Interactions

- [CBW-002-add_context_from_picker](CBW-002-add_context_from_picker.md)
- [CBW-002-add_selection_as_request_context](CBW-002-add_selection_as_request_context.md)
- [CBW-002-capture_request_context_snapshot](CBW-002-capture_request_context_snapshot.md)
- [CBW-002-edit_request_context](CBW-002-edit_request_context.md)
- [CBW-002-remove_request_context](CBW-002-remove_request_context.md)
- [CBW-002-show_request_context](CBW-002-show_request_context.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Contracts: [request_context_contract.toml](../contracts/request_context_contract.toml)
- Source line: `162`
