---
interaction_id: "CBW-001-cancel_active_chat_request"
interaction_type: "command"
feature: "Manage Chat Request Lifecycle"
category_key: "CBW"
feature_id: "CBW-001"
status: "기획 완료"
summary: "현재 실행 중인 chat request의 응답 생성과 후속 처리를 중단하도록 요청한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.chat_field"
menu: "-"
shortcut: "-"
---

# Cancel Active Chat Request

## Intent

- 현재 실행 중인 request를 사용자가 명시적으로 중단할 수 있게 한다.
- 더 이상 원하지 않는 응답 생성과 후속 상태 업데이트를 멈춘다.

## Trigger / Entry Points

- Chat Field 영역에 노출된 `Stop` 버튼을 누를 때 호출된다.
- active request가 cancellable 상태일 때만 진입 가능하다.

## Preconditions

- 취소 대상 request가 `processing` 상태인 경우
- 현재 provider 호출을 취소하거나 후속 결과를 무시할 수 있는 control path가 존재하는 상태

## Expected Outcome

- 취소 요청이 접수되면 대상 request는 `cancelled` 상태로 전환되어야 한다.
- 취소 이후 추가 응답 chunk 또는 후속 자동 실행이 화면에 이어지지 않아야 한다.

## State Changes

- 대상 request에 cancel requested flag가 기록된다.
- message area state가 `processing`에서 terminal `cancelled` state로 전환된다.

## User-visible Feedback

- 사용자는 취소가 접수된 결과를 화면에서 확인할 수 있어야 한다.
- 취소가 반영되면 `cancelled` 결과가 남아야 한다.

## Edge Cases / Failure Handling

- 이미 `completed`, `failed`, `cancelled` 상태인 request에는 취소를 다시 적용하지 않아야 한다.
- provider가 하위 호출 취소를 지원하지 않으면 결과 적용만 차단하는 local cancellation 정책으로 폴백해야 한다.
- 취소 직후 늦게 도착한 응답 chunk는 숨기거나 무시해야 한다.

## Acceptance Criteria

- [ ] request가 실행 중인 상황에서 사용자가 취소를 수행하면, 대상 request는 `cancelled` 상태로 전환되어야 한다.
- [ ] 이미 완료된 request에 대해 사용자가 취소를 수행하면, 상태가 다시 변경되지 않아야 하고 불필요한 실패도 노출되지 않아야 한다.
- [ ] provider 수준 취소가 불가능한 상황에서 사용자가 취소를 수행하면, late response가 화면에 계속 반영되지 않도록 local cancellation이 적용되어야 한다.

## Permissions / Dependencies

- provider call cancellation 또는 late response suppression 메커니즘이 필요하다.
- request state renderer와 message stream consumer가 동일 cancellation source를 참조해야 한다.

## Observability / Analytics

- cancel request 이벤트
- cancel success/fallback 이벤트
- late chunk dropped count

## Related Interactions

- [CBW-001-open_contextual_chat](CBW-001-open_contextual_chat.md)
- [CBW-001-regenerate_chat_response](CBW-001-regenerate_chat_response.md)
- [CBW-001-show_request_processing_state](CBW-001-show_request_processing_state.md)
- [CBW-001-submit_chat_request](CBW-001-submit_chat_request.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:157`
- Contracts: [request_lifecycle.toml](../contracts/request_lifecycle.toml)
- Flows: [contextual_chat_request_flow.md](../flows/contextual_chat_request_flow.md)
