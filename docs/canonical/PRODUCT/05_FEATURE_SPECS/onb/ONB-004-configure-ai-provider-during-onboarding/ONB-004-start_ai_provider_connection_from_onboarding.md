---
interaction_id: "ONB-004-start_ai_provider_connection_from_onboarding"
interaction_type: "command"
feature: "Configure AI Provider During Onboarding"
category_key: "ONB"
feature_id: "ONB-004"
status: "drafted"
phase: "later"
summary: "<<AI>> 사용자가 온보딩에서 선택한 프로바이더에 대해 SET-007의 연결 흐름으로 진입하도록 라우팅"
related_region: "onboarding_window.ai_provider_setup_screen"
menu: "-"
shortcut: "-"
---

# Start AI Provider Connection From Onboarding

## Intent

- 사용자가 온보딩 화면에서 선택한 AI 프로바이더를 SET-007의 연결 flow로 넘겨 실제 연결을 시작한다.
- ONB-004는 routing과 온보딩 복귀 상태를 소유하고, provider credential 저장, OAuth/API key 처리, 연결 검증은 SET-007이 소유한다.

## Trigger / Entry Points

- 사용자가 AI Provider Setup step에서 특정 프로바이더의 Connect 또는 Reconnect를 선택할 때 호출된다.
- provider connection flow가 실패한 뒤 사용자가 같은 프로바이더를 다시 연결하려 할 때 호출된다.

## Preconditions

- 현재 온보딩 step이 AI Provider Setup이어야 한다.
- 선택한 provider가 SET-007 provider catalog에 존재해야 한다.
- 선택한 provider가 connected 상태가 아니거나 Reconnect가 허용된 상태여야 한다.

## Expected Outcome

- 선택한 provider id와 onboarding return context가 SET-007 연결 flow로 전달된다.
- 연결 flow가 완료되면 사용자는 AI Provider Setup step으로 돌아와 최신 provider connection status를 확인한다.
- 연결 성공 결과는 [ONB-004-show_onboarding_ai_provider_setup](ONB-004-show_onboarding_ai_provider_setup.md)에 반영되어 step completion을 갱신한다.
- 연결 실패 또는 취소는 온보딩을 종료하지 않고 Retry 또는 Set up later 선택을 유지한다.

## State Changes

- 선택한 provider, connection attempt id, onboarding return context를 step state에 기록한다.
- 연결 flow 진입 중에는 해당 provider row를 pending 상태로 표시한다.
- SET-007이 반환한 연결 결과를 읽어 provider status와 `step_completion_state`를 다시 계산한다.

## User-visible Feedback

- 연결 시작 시 선택한 provider row에 진행 상태를 표시한다.
- 연결 flow로 이동하는 동안 온보딩 복귀 경로가 유지되어야 한다.
- 성공 시 connected 상태와 Next enabled 상태를 표시한다.
- 실패 또는 취소 시 provider row에 오류 상태와 Retry/Set up later를 표시한다.

## Edge Cases / Failure Handling

- 선택한 provider가 catalog에서 제거되었으면 연결을 시작하지 않고 catalog refresh를 안내한다.
- 연결 flow를 열 수 없으면 온보딩을 닫지 않고 오류를 표시한다.
- 사용자가 연결 flow 중 앱을 종료해도 재실행 시 AI Provider Setup step에서 최신 상태를 다시 확인한다.
- 연결 결과가 늦게 도착하면 최신 provider status 조회 결과를 기준으로 화면을 갱신한다.

## Acceptance Criteria

- [ ] disconnected provider row에서 Connect를 실행하면, 해당 provider와 onboarding return context가 SET-007 연결 flow로 전달되어야 한다.
- [ ] SET-007 provider 연결이 성공한 상황에서 온보딩으로 돌아오면, 해당 provider가 connected로 표시되고 step이 `complete`로 저장되어야 한다.
- [ ] 연결 flow가 취소되면, 온보딩은 AI Provider Setup step을 유지하고 Connect와 Set up later를 다시 표시해야 한다.
- [ ] catalog에 없는 provider에 대해 연결을 시작하려 하면, 연결 flow를 열지 않고 catalog refresh 또는 오류 상태를 표시해야 한다.

## Permissions / Dependencies

- SET-007 provider connection flow와 provider catalog가 필요하다.
- provider별 OAuth, API key, credential storage 정책은 SET-007 계약을 따른다.
- 관련 UI region: `onboarding_window.ai_provider_setup_screen`

## Observability / Analytics

- provider connection 성공/실패/취소

## Related Interactions

- [ONB-004-show_onboarding_ai_provider_setup](ONB-004-show_onboarding_ai_provider_setup.md)
- [ONB-004-skip_ai_provider_setup_during_onboarding](ONB-004-skip_ai_provider_setup_during_onboarding.md)

## Boundary Notes

- ONB step status vocabulary는 `pending`, `complete`, `blocked`, `error`, `skipped`를 따른다.

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:267`
- Contracts: [onboarding_session_contract.toml](../contracts/onboarding_session_contract.toml), [ai_provider_setup_contract.toml](../contracts/ai_provider_setup_contract.toml), [ai_provider_connection_contract.toml](../../set/contracts/ai_provider_connection_contract.toml)
- Flows: [ai_provider_setup_flow.md](../flows/ai_provider_setup_flow.md), [onboarding_session_flow.md](../flows/onboarding_session_flow.md)
