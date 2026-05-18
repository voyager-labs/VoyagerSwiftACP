---
interaction_id: "ONB-004-show_onboarding_ai_provider_setup"
interaction_type: "display"
feature: "Configure AI Provider During Onboarding"
category_key: "ONB"
feature_id: "ONB-004"
status: "drafted"
phase: "later"
summary: "<<AI>> 온보딩 AI 프로바이더 설정 스크린에서 SET-007의 프로바이더 카탈로그와 연결 상태, 연결 액션, 나중에 설정 선택지를 표시"
related_region: "onboarding_window.ai_provider_setup_screen"
menu: "-"
shortcut: "-"
---

# Show Onboarding AI Provider Setup

## Intent

- 사용자가 첫 실행 중 AI 프로바이더 연결 필요성을 이해하고, 지원 프로바이더 연결 또는 나중에 설정 중 하나를 선택할 수 있도록 표시한다.
- ONB-004는 온보딩 surface와 `provider_setup_choice`를 소유하고, 프로바이더 catalog와 실제 연결/해제 상태의 source of truth는 SET-007을 따른다.

## Trigger / Entry Points

- ONB-001이 AI Provider Setup step을 현재 step으로 표시할 때 호출된다.
- SET-007 provider catalog 또는 연결 상태가 갱신될 때 호출된다.
- 사용자가 연결 flow에서 온보딩으로 돌아오거나 Set up later를 선택한 뒤 화면 상태를 다시 계산할 때 호출된다.

## Preconditions

- 온보딩 세션이 시작되어 있고 current step이 AI Provider Setup이어야 한다.
- SET-007 provider catalog와 provider connection status를 조회할 수 있어야 한다.
- catalog가 아직 로딩 중이면 화면은 pending 상태로 표시되어야 한다.

## Expected Outcome

- ChatGPT Codex, OpenAI, Anthropic 등 SET-007이 제공하는 프로바이더 catalog가 온보딩 화면에 표시된다.
- 각 프로바이더 row는 연결 상태와 Connect/Reconnect 진입 action을 보여준다.
- 하나 이상의 프로바이더가 connected이면 AI Provider Setup step은 `complete`로 표시된다.
- 사용자가 Set up later를 선택한 경우 step은 `skipped`로 표시되며, 온보딩 진행 조건에서는 `complete`와 동등하게 취급된다. 이후 AI 요청 surface는 SET-007 provider 상태를 계속 참조한다.

## State Changes

- display interaction은 provider credential 또는 connection source of truth를 변경하지 않는다.
- provider catalog와 connection status를 읽어 AI Provider Setup view state와 `step_completion_state`를 계산한다.
- setUpLater 선택 여부와 마지막 확인 시각을 `progress_snapshot`에 반영할 수 있어야 한다.

## User-visible Feedback

- catalog 로딩 중에는 loading 상태와 Set up later 선택지를 표시한다.
- connected 프로바이더는 완료 상태로 표시한다.
- disconnected 또는 error 상태인 프로바이더는 Connect/Reconnect action을 표시한다.
- catalog 로딩 실패는 온보딩 전체를 hard-block하지 않고 Retry와 Set up later를 제공한다.

## Edge Cases / Failure Handling

- provider catalog가 비어 있으면 Set up later와 Retry를 표시하고 연결 완료로 처리하지 않는다.
- 이전 snapshot에 setUpLater가 저장되어 있어도 사용자가 다시 step에 진입하면 연결 상태와 선택 상태를 함께 표시한다.
- provider 상태가 error이면 connection action과 오류 설명을 함께 표시한다.
- SET-007 상태 조회가 실패해도 온보딩 세션은 유지되어야 한다.

## Acceptance Criteria

- [ ] AI Provider Setup step에 진입한 상황에서 provider catalog가 로드되면, 지원 프로바이더와 각 연결 상태가 표시되어야 한다.
- [ ] 하나 이상의 프로바이더가 connected인 상황에서 화면이 표시되면, step이 complete로 표시되고 Next가 enabled 상태여야 한다.
- [ ] 연결된 프로바이더가 없는 상황에서 화면이 표시되면, Connect action과 Set up later 선택지가 표시되어야 한다.
- [ ] provider catalog 로딩이 실패하면, Retry와 Set up later가 표시되고 온보딩 세션은 유지되어야 한다.

## Permissions / Dependencies

- SET-007의 provider catalog와 connection status source of truth가 필요하다.
- provider 연결 상세 flow는 SET-007이 소유한다.
- ONB-001은 ONB-004가 계산한 `step_completion_state`를 읽어 다음 step 이동 여부를 결정한다.
- 관련 UI region: `onboarding_window.ai_provider_setup_screen`

## Observability / Analytics

- provider catalog 조회 성공/실패

## Related Interactions

- [ONB-004-skip_ai_provider_setup_during_onboarding](ONB-004-skip_ai_provider_setup_during_onboarding.md)
- [ONB-004-start_ai_provider_connection_from_onboarding](ONB-004-start_ai_provider_connection_from_onboarding.md)

## Boundary Notes

- ONB step status vocabulary는 `pending`, `complete`, `blocked`, `error`, `skipped`를 따른다.

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:266`
- Contracts: [onboarding_session_contract.toml](../contracts/onboarding_session_contract.toml), [ai_provider_setup_contract.toml](../contracts/ai_provider_setup_contract.toml), [ai_provider_connection_contract.toml](../../set/contracts/ai_provider_connection_contract.toml)
- Flows: [ai_provider_setup_flow.md](../flows/ai_provider_setup_flow.md), [onboarding_session_flow.md](../flows/onboarding_session_flow.md)
