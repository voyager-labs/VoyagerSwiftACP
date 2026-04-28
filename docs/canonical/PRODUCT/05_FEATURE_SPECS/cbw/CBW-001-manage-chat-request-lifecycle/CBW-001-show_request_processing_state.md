---
interaction_id: "CBW-001-show_request_processing_state"
interaction_type: "display"
feature: "Manage Chat Request Lifecycle"
category_key: "CBW"
feature_id: "CBW-001"
status: "기획 완료"
summary: "대상 chat request의 처리 중·완료·실패·취소 상태를 메시지 영역에 일관되게 표시하고, regenerate 이후에는 현재 유효한 request 상태만 남긴다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.message_area"
menu: "-"
shortcut: "-"
---

# Show Request Processing State

## Intent

- 현재 request가 어느 lifecycle 단계에 있는지 사용자가 실시간으로 이해할 수 있게 한다.
- submit, regenerate, cancel 이후 상태 전이를 message area에 일관된 표현으로 노출한다.
- regenerate가 과거 request를 기준으로 실행될 때도 branch 없이 단일 active conversation에서 어떤 request가 현재 유효한지 분명히 보여준다.

## Trigger / Entry Points

- request가 `processing`, `completed`, `failed`, `cancelled` 상태로 바뀔 때 갱신된다.
- message area가 다시 그려지거나 chat pane을 재표시할 때 현재 상태를 복원한다.
- regenerate로 인해 active conversation의 후속 turn 범위가 잘리거나 초기화될 때 표시 범위를 다시 계산한다.

## Preconditions

- 표시 대상 request record가 존재하는 상태
- message area가 현재 대화의 request 상태를 렌더링할 수 있는 상태
- request lifecycle source가 `request` 기준 상태와 latest visible turn 범위를 함께 제공할 수 있는 상태

## Expected Outcome

- active conversation 안에서는 현재 유효한 request들만 표시되어야 한다.
- 각 request에는 하나의 `processing` 상태만 표시되어야 하며, 같은 active conversation 안에서 동시에 여러 `processing` 표시가 남으면 안 된다.
- `completed`, `failed`, `cancelled` 상태가 되면 진행 표시가 제거되고 최종 상태가 남아야 한다.
- regenerate가 시작되면 대상 request는 다시 `processing`으로 보이고, 그 뒤의 무효화된 후속 turn은 active conversation 표시에서 제외되어야 한다.

## State Changes

- request lifecycle state 변화가 message rendering state에 동기화된다.
- request visibility 범위가 regenerate 기준점에 맞춰 다시 계산된다.
- `processing` 상태가 `completed`, `failed`, `cancelled` 상태 중 하나로 전환된다.

## User-visible Feedback

- 사용자는 어떤 request가 `processing`, `completed`, `failed`, `cancelled` 상태인지 구분할 수 있어야 한다.
- 상태 전이가 발생할 때 깜빡임 없이 동일 request bubble 내에서 갱신되어야 한다.
- regenerate로 인해 이후 대화가 초기화되면, 사용자는 대상 request가 다시 `processing`이 되었고 이후 turn이 더 이상 현재 대화에 포함되지 않는다는 점을 인지할 수 있어야 한다.

## Edge Cases / Failure Handling

- 동일 request에 대한 중복 상태 이벤트가 들어와도 마지막 유효 상태만 반영해야 한다.
- cancel 직후 late response chunk가 도착하면 상태와 화면이 다시 `processing`으로 되돌아가면 안 된다.
- chat pane 재오픈 시 이전 `processing` 표시가 잘못 복원되지 않도록 `completed`, `failed`, `cancelled` 상태를 우선해야 한다.
- regenerate 직후 잘려 나간 후속 turn에서 late 상태 이벤트가 도착해도, 해당 turn이 다시 active conversation에 나타나면 안 된다.
- 과거 request를 기준으로 regenerate했더라도, 최신 visible request와 상태 표시가 branch처럼 둘 이상 살아 있으면 안 된다.

## Acceptance Criteria

- [ ] request가 실행 중인 상황에서 상태 표시를 갱신하면, message area에 `processing` 상태가 보여야 한다.
- [ ] request가 완료, 취소, 실패한 상황에서 상태 표시를 갱신하면, 진행 표시가 제거되고 최종 상태가 각각 `completed`, `cancelled`, `failed`로 보여야 한다.
- [ ] 동일 request에 대해 늦게 도착한 상태 이벤트가 있는 상황에서 상태 표시를 갱신하면, 마지막 유효 상태만 화면에 남아야 한다.
- [ ] regenerate로 `completed` 또는 `failed` 상태의 request가 다시 실행된 상황에서 상태 표시를 갱신하면, 대상 request는 다시 `processing`으로 보여야 하고 이후 후속 turn은 active conversation에서 제외되어야 한다.
- [ ] regenerate 이후 잘려 나간 후속 turn에서 늦게 도착한 상태 이벤트가 있는 상황에서 상태 표시를 갱신하면, 해당 turn은 다시 화면에 나타나지 않아야 한다.

## Permissions / Dependencies

- request lifecycle source와 message renderer에 의존한다.
- active conversation의 visible turn range를 계산하는 session rewrite 결과를 참조해야 한다.
- 실패 상태 표시는 [CBW-003-show_request_resolution_failure](../CBW-003-resolve-contextual-chat-requests/CBW-003-show_request_resolution_failure.md)와 함께 동작해야 한다.

## Observability / Analytics

- request state transition 이벤트
- state restore mismatch
- stale state overwrite 발생 수

## Related Interactions

- [CBW-001-cancel_active_chat_request](CBW-001-cancel_active_chat_request.md)
- [CBW-001-open_contextual_chat](CBW-001-open_contextual_chat.md)
- [CBW-001-regenerate_chat_response](CBW-001-regenerate_chat_response.md)
- [CBW-001-submit_chat_request](CBW-001-submit_chat_request.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:156`
- Contracts: [request_lifecycle.toml](../contracts/request_lifecycle.toml)
- Flows: [contextual_chat_request_flow.md](../flows/contextual_chat_request_flow.md)
