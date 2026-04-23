---
interaction_id: "CBW-002-capture_request_context_snapshot"
interaction_type: "background"
feature: "Manage Request Context"
category_key: "CBW"
feature_id: "CBW-002"
status: "기획 완료"
summary: "요청 제출 시점의 현재 요청 컨텍스트 범위와 항목 구성을 고정해 해당 request 전용 스냅샷을 생성한다."
related_region: "-"
menu: "-"
shortcut: "-"
---

# Capture Request Context Snapshot

## Intent

- 요청 제출 시점의 current context와 explicit attachment entry 전체 구성을 포함한 request context 범위를 불변 snapshot으로 고정한다.
- 제출 이후 page·selection·attachment가 바뀌어도 이미 보낸 request의 기준 context가 흔들리지 않게 한다.

## Trigger / Entry Points

- 신규 request submit 또는 regenerate 직전에 자동으로 호출된다.
- draft request context가 execution-ready 상태로 넘어갈 때 수행된다.

## Preconditions

- 전송할 user input과 `draft_context` request context가 존재하는 상태
- snapshot 대상 current context entry와 explicit attachment entry(인라인 attachment 포함)를 해석하고 고정할 수 있는 상태

## Expected Outcome

- request 전용 snapshot이 생성되고 이후 request preparation 단계에서 current context와 explicit attachment entry 전체의 source of truth로 참조되어야 한다.
- snapshot 생성 후 현재 request context는 `request_context_locked` 상태가 되어야 하며, 이후 draft context를 바꿔도 이미 제출된 request에는 영향을 주지 않아야 한다.

## State Changes

- draft request context 안의 current context와 explicit attachment entry 구성이 immutable snapshot id 또는 동일한 고정 표현으로 변환된다.
- 현재 request context state가 `request_context_locked`로 전환된다.
- 제외되거나 축약된 context 항목이 있으면 snapshot metadata에 기록된다.

## User-visible Feedback

- 사용자에게는 과도한 내부 정보를 노출하지 않더라도, snapshot 고정 결과가 후속 request 처리와 context 표시 일관성에 반영되어야 한다.
- snapshot 생성 실패 시 request submit이 안전하게 중단되거나 축소 정책이 안내되어야 한다.

## Edge Cases / Failure Handling

- attachment 또는 기타 explicit entry 일부(인라인 attachment 포함)가 삭제되었거나 `broken_reference` 상태여도 가능한 항목만 포함하고 제외 사유를 남겨야 한다.
- context가 너무 커서 전부 고정할 수 없으면 축약 또는 우선순위 정책을 적용해야 한다.
- 동일 request에 대해 snapshot이 중복 생성되지 않도록 idempotent해야 한다.

## Acceptance Criteria

- [ ] 사용자가 요청을 전송하는 상황에서 snapshot capture가 수행되면, 해당 request는 제출 시점의 current context와 explicit attachment entry 전체 기준으로 고정된 snapshot을 가져야 하며 request context state는 `request_context_locked`로 전환되어야 한다.
- [ ] 제출 이후 현재 page 또는 selection이 바뀌는 상황에서도, 이미 보낸 request의 snapshot은 바뀌지 않아야 한다.
- [ ] 일부 context를 snapshot에 포함할 수 없는 상황에서 capture가 수행되면, 가능한 항목만 고정하고 제외 사유가 metadata에 기록되어야 한다.

## Permissions / Dependencies

- context entry resolver와 snapshot serializer가 필요하다.
- 후속 request preparation은 이 snapshot을 source of truth로 사용해야 한다.

## Observability / Analytics

- snapshot 생성 이벤트
- snapshot item count
- snapshot truncation/exclusion count

## Related Interactions

- [CBW-002-add_attachment_from_picker](CBW-002-add_attachment_from_picker.md)
- [CBW-002-add_inline_attachment](CBW-002-add_inline_attachment.md)
- [CBW-002-add_selection_to_context](CBW-002-add_selection_to_context.md)
- [CBW-002-remove_request_context](CBW-002-remove_request_context.md)
- [CBW-002-show_request_context](CBW-002-show_request_context.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:164`
- Contracts: [request_context_contract.toml](../contracts/request_context_contract.toml)
- Flows: [contextual_chat_request_flow.md](../flows/contextual_chat_request_flow.md), [request_context_management_flow.md](../flows/request_context_management_flow.md)
