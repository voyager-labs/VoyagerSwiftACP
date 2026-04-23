---
interaction_id: "CBW-003-show_response_references"
interaction_type: "display"
feature: "Resolve Contextual Chat Requests"
category_key: "CBW"
feature_id: "CBW-003"
status: "드래프트"
summary: "<<AI>> 응답이 근거로 사용한 context 범위와 참조 대상을 사용자가 확인할 수 있게 표시한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.message_area"
menu: "-"
shortcut: "-"
---

# Show Response References

## Intent

- assistant response가 어떤 context 범위와 참조 대상을 근거로 사용했는지 노출한다.
- 사용자가 답변의 근거 범위를 최소한 검증할 수 있게 한다.

## Trigger / Entry Points

- response가 완료되었거나 reference metadata가 준비되면 표시된다.
- 사용자가 response의 reference affordance를 펼칠 때 더 자세한 목록을 보여줄 수 있다.

## Preconditions

- 표시 대상 response에 reference metadata 또는 snapshot provenance가 존재하는 상태
- message area가 response metadata를 함께 렌더링할 수 있는 상태

## Expected Outcome

- 사용자는 response가 기반으로 삼은 파일, selection, collection, snapshot 범위를 확인할 수 있어야 한다.
- reference가 없는 경우에는 비어 있음을 명확하게 보여야 한다.

## State Changes

- response metadata 영역에 reference summary 또는 detail list가 표시된다.
- collapsed/expanded state가 존재하면 사용자 조작에 따라 전환된다.

## User-visible Feedback

- reference 수, 대표 라벨, 범위 요약이 response와 연결된 위치에 보여야 한다.
- broken or unavailable reference는 일반 reference와 구분되어야 한다.

## Edge Cases / Failure Handling

- reference가 너무 많으면 요약 우선 정책으로 접어야 한다.
- 일부 reference가 더 이상 접근 불가하면 broken state로 표시해야 한다.
- provider가 explicit citation을 주지 않아도 최소 snapshot provenance는 보여야 한다.

## Acceptance Criteria

- [ ] response에 reference metadata가 있는 상황에서 reference 표시를 수행하면, 사용자는 근거로 사용된 context 범위와 주요 대상을 확인할 수 있어야 한다.
- [ ] reference가 없는 상황에서 reference 표시를 수행하면, reference 없음 상태가 오해 없이 보여야 한다.
- [ ] 일부 reference가 깨진 상황에서 reference 표시를 수행하면, 정상 reference와 broken reference가 구분되어 보여야 한다.

## Permissions / Dependencies

- request snapshot provenance와 response metadata에 의존한다.
- broken reference 표시는 [CBW-002-show_request_context](../CBW-002-manage-request-context/CBW-002-show_request_context.md)의 broken 표시 규칙과 일치해야 한다.

## Observability / Analytics

- reference panel open rate
- reference count per response
- broken reference rate

## Related Interactions

- [CBW-003-build_contextual_request_payload](CBW-003-build_contextual_request_payload.md)
- [CBW-003-generate_contextual_chat_response](CBW-003-generate_contextual_chat_response.md)
- [CBW-003-show_request_resolution_failure](CBW-003-show_request_resolution_failure.md)
- [CBW-003-stream_contextual_chat_response](CBW-003-stream_contextual_chat_response.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `169`
