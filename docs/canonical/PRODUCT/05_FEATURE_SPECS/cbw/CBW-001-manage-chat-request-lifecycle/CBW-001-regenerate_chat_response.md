---
interaction_id: "CBW-001-regenerate_chat_response"
interaction_type: "command"
feature: "Manage Chat Request Lifecycle"
category_key: "CBW"
feature_id: "CBW-001"
status: "기획 완료"
summary: "이전에 고정된 컨텍스트 스냅샷과 현재 활성 model selection 기준으로 대상 요청의 응답을 다시 생성하고, 이후 대화는 branch 없이 현재 흐름 기준으로 초기화한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_chat.message_area"
menu: "-"
shortcut: "-"
---

# Regenerate Chat Response

## Intent

- 같은 user request가 속한 turn 안에서 assistant response를 다시 생성할 수 있게 한다.
- 사용자가 현재 response 결과가 불충분하거나 실패한 경우, 새 user turn을 만들지 않고 동일 request를 다시 시도할 수 있게 한다.
- 구현 복잡도를 낮추기 위해 regenerate 이후에는 분기(branch)를 만들지 않고, 해당 시점 뒤의 후속 대화는 초기화 가능한 구조로 유지한다.

## Trigger / Entry Points

- 기존 assistant response에 대한 regenerate CTA를 선택할 때 호출된다.
- 대상 user request와 재생성 기준이 되는 response를 식별할 수 있을 때만 호출된다.

## Preconditions

- 재생성 대상 user request가 존재하는 상태
- 재생성 기준으로 삼을 response가 해당 user request의 response history 안에 존재하는 상태
- 해당 user request가 속한 turn의 lifecycle state가 `completed` 또는 `failed` 상태인 경우
- 해당 user request가 속한 turn에 `processing` 상태의 response가 없는 상태
- 재사용할 context snapshot, active model selection, session continuity를 다시 구성할 수 있는 상태

## Expected Outcome

- 기존 user request를 기반으로 새 response가 생성되어야 한다.
- request lifecycle state는 다시 `processing`으로 전환되어야 한다.
- 재생성 기준이 된 response와 그 외 기존 결과는 이력으로 남고, 새 response만 현재 turn의 latest visible response로 간주되어야 한다.
- 재생성 기준 request 뒤에 이어졌던 downstream user turn과 response는 active conversation에서 제외되거나 초기화 대상으로 표시되어야 한다.

## State Changes

- 대상 user request가 속한 turn에 새로운 response id가 추가되고 latest visible response 포인터가 새 response 기준으로 갱신된다.
- request lifecycle state가 `completed` 또는 `failed`에서 `processing`으로 전환된다.
- 대상 request 이후에 이어지던 conversation continuity 범위가 잘리고, 후속 turn history는 active session에서 제거되거나 무효화된다.

## User-visible Feedback

- 사용자는 어떤 응답을 재생성 중인지 식별할 수 있어야 한다.
- 사용자가 과거 response를 기준으로 재생성을 시작한 경우, 어떤 과거 응답에서 파생된 재시도인지 구분할 수 있어야 한다.
- 기존 응답은 즉시 제거되지 않고, 새 response가 진행 중임을 보여주는 `processing` 표시가 같은 turn 범위 안에서 나타나야 한다.
- 재생성 완료 또는 실패 후에는 어떤 결과가 최신 결과인지 구분할 수 있어야 한다.
- 재생성으로 인해 이후 대화가 초기화되는 경우, 사용자는 이후 turn이 유지되지 않는다는 점을 실행 전에 알 수 있어야 한다.

## Edge Cases / Failure Handling

- 원래 context snapshot에 포함된 일부 context source가 현재 사라졌더라도, regenerate는 직전 submit 시점에 고정된 snapshot을 우선 재사용해야 한다.
- 현재 active model이 바뀐 뒤 재생성하면 새 model 기준으로 실행된다는 점이 일관되게 적용되어야 한다.
- 대상 response가 이미 실패 상태라면 재생성은 허용하되 이전 실패 이력은 보존해야 한다.
- 과거 response 중 최신 visible response가 아닌 항목에서 regenerate를 시작해도, 새 response는 동일 request와 turn에 귀속되며 이전 response ordering이 손상되면 안 된다.
- 동일 request가 속한 turn에 `processing` 상태의 response가 이미 존재하면 regenerate CTA는 비활성화되거나 요청이 무시되어야 하며, 중복 response를 만들면 안 된다.
- regenerate 시작 직후 다른 과거 response에서 late event가 도착하더라도, latest visible response 포인터와 user-visible state가 이전 response 기준으로 되돌아가면 안 된다.
- 재생성 대상 request 뒤에 후속 turn이 이미 존재하면, 새 branch를 만들지 말고 그 후속 turn들을 active session에서 잘라내는 단일 정책만 지원해야 한다.

## Acceptance Criteria

- [ ] 사용자가 기존 assistant response에 대해 재생성을 수행하면, 같은 user request를 기반으로 새로운 response가 생성되어야 한다.
- [ ] 재생성 직전에 active model이 바뀐 상황에서 사용자가 재생성을 수행하면, 새 response는 변경된 model 기준으로 실행되어야 한다.
- [ ] 해당 user request가 속한 turn에 `processing` 상태의 response가 이미 있는 상황에서 사용자가 다시 재생성을 수행하면, 중복 response가 생성되지 않아야 한다.
- [ ] `completed` 상태의 request에 대해 사용자가 재생성을 수행하면, request lifecycle state는 다시 `processing`으로 전환되고 기존 `completed` 결과는 이력으로 보존되어야 한다.
- [ ] `failed` 상태의 request에 대해 사용자가 재생성을 수행하면, 이전 failure 이력은 유지된 채 새로운 response가 시작되어야 한다.
- [ ] 동일 user request 안에 과거 response가 여러 개 있는 상황에서 사용자가 특정 과거 response에 대해 재생성을 수행하면, 선택한 response를 기준으로 새 response가 생성되어야 하고 다른 과거 response 이력은 유지되어야 한다.
- [ ] 재생성 대상 request 뒤에 후속 대화 turn이 존재하는 상황에서 사용자가 재생성을 수행하면, 후속 turn은 branch로 분기되지 않고 active conversation에서 초기화되어야 한다.

## Permissions / Dependencies

- [CBW-003-prepare_contextual_chat_request](../CBW-003-resolve-contextual-chat-requests/CBW-003-prepare_contextual_chat_request.md), [CBW-003-generate_contextual_chat_response](../CBW-003-resolve-contextual-chat-requests/CBW-003-generate_contextual_chat_response.md)에 의존한다.
- 대상 request의 snapshot과 session continuity metadata를 재사용할 수 있어야 한다.
- 재생성 대상 response 식별자와 request별 response history를 함께 관리할 수 있어야 한다.
- regenerate 이후 기준 request 뒤에 이어지는 후속 turn history를 active session에서 제외하거나 초기화하는 session rewrite 정책이 필요하다.

## Observability / Analytics

- regenerate 시작 이벤트
- regenerate success/failure
- regenerate blocked 이유

## Related Interactions

- [CBW-001-cancel_active_chat_request](CBW-001-cancel_active_chat_request.md)
- [CBW-001-open_contextual_chat](CBW-001-open_contextual_chat.md)
- [CBW-001-show_request_processing_state](CBW-001-show_request_processing_state.md)
- [CBW-001-submit_chat_request](CBW-001-submit_chat_request.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:158`
- Contracts: [request_lifecycle.toml](../contracts/request_lifecycle.toml)
- Flows: [contextual_chat_request_flow.md](../flows/contextual_chat_request_flow.md), [request_context_management_flow.md](../flows/request_context_management_flow.md)
