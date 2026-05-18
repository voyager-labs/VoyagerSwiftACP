---
interaction_id: "ONB-004-skip_ai_provider_setup_during_onboarding"
interaction_type: "command"
feature: "Configure AI Provider During Onboarding"
category_key: "ONB"
feature_id: "ONB-004"
status: "drafted"
phase: "later"
summary: "<<AI>> 사용자가 나중에 설정을 명시적으로 선택하면 AI 프로바이더 설정 스텝을 완료 상태로 표시하고 이후 설정 진입 경로를 유지"
related_region: "onboarding_window.ai_provider_setup_screen"
menu: "-"
shortcut: "-"
---

# Skip AI Provider Setup During Onboarding

## Intent

- 사용자가 첫 실행 중 AI 프로바이더 연결을 완료하지 않더라도 명시적인 Set up later 선택으로 온보딩을 계속 진행할 수 있게 한다.
- ONB-004는 `provider_setup_choice`를 저장하고, 이후 AI 기능 사용 시 provider 연결 필요 상태는 SET-007 source of truth를 따른다.

## Trigger / Entry Points

- 사용자가 AI Provider Setup step에서 Set up later를 선택할 때 호출된다.
- provider catalog 로딩 실패 또는 연결 실패 후 사용자가 나중에 설정을 선택할 때 호출된다.

## Preconditions

- 현재 온보딩 step이 AI Provider Setup이어야 한다.
- Set up later 선택지가 현재 정책에서 허용되어야 한다.
- 사용자가 선택을 명시적으로 실행해야 하며, 단순 catalog 로딩 실패만으로 자동 skip 처리하지 않는다.

## Expected Outcome

- AI Provider Setup step이 `skipped`로 저장되고 Next가 enabled 상태가 된다.
- `progress_snapshot`에는 setUpLater 선택과 선택 시각이 저장된다.
- 이후 Settings AI 또는 AI 요청 surface에서 provider 연결 상태를 다시 안내할 수 있도록 SET-007 진입 경로가 유지된다.
- provider credential 또는 connection status는 변경하지 않는다.

## State Changes

- setUpLater를 true로 저장하고 AI Provider Setup `step_completion_state`를 `skipped`로 갱신한다.
- 기존 provider connection status는 그대로 유지한다.
- 사용자가 이후 provider를 연결하면 setUpLater 선택보다 connected 상태가 우선 표시된다.

## User-visible Feedback

- Set up later 선택 후 step이 완료되었음을 표시하고 Next를 enabled 상태로 전환한다.
- 연결이 없어도 이후 Settings AI에서 설정할 수 있음을 표시한다.
- catalog 로딩 실패 상태에서 skip한 경우에도 온보딩 완료 가능 상태를 명확히 보여준다.

## Edge Cases / Failure Handling

- snapshot 저장에 실패하면 step을 complete로 확정하지 않고 Retry 가능한 오류를 표시한다.
- Set up later가 정책상 허용되지 않는 빌드에서는 선택지를 표시하지 않는다.
- 사용자가 Set up later 이후 Back으로 돌아오면 선택 상태와 provider status가 함께 복원되어야 한다.
- AI provider가 이미 connected이면 Set up later보다 connected 완료 상태를 우선한다.

## Acceptance Criteria

- [ ] 연결된 provider가 없는 상황에서 사용자가 Set up later를 선택하면, AI Provider Setup step이 `skipped`로 저장되고 Next가 enabled 상태가 되어야 한다.
- [ ] Set up later를 선택한 상황에서 Back 또는 Next로 이동한 뒤 다시 AI Provider Setup step으로 돌아오면, 선택 상태가 `progress_snapshot`에서 복원되어야 한다.
- [ ] snapshot 저장이 실패하면, step이 `skipped`로 확정되지 않고 Retry 가능한 오류가 표시되어야 한다.
- [ ] provider가 이미 connected인 상황에서는 Set up later 선택 없이도 connected 완료 상태가 우선 표시되어야 한다.

## Permissions / Dependencies

- ONB-001 `progress_snapshot` store에 `provider_setup_choice`를 저장할 수 있어야 한다.
- 이후 provider 연결 관리는 SET-007 Settings AI surface가 소유한다.
- 관련 UI region: `onboarding_window.ai_provider_setup_screen`

## Observability / Analytics

- Set up later 선택

## Related Interactions

- [ONB-004-show_onboarding_ai_provider_setup](ONB-004-show_onboarding_ai_provider_setup.md)
- [ONB-004-start_ai_provider_connection_from_onboarding](ONB-004-start_ai_provider_connection_from_onboarding.md)

## Boundary Notes

- ONB step status vocabulary는 `pending`, `complete`, `blocked`, `error`, `skipped`를 따른다.

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:268`
- Contracts: [onboarding_session_contract.toml](../contracts/onboarding_session_contract.toml), [ai_provider_setup_contract.toml](../contracts/ai_provider_setup_contract.toml), [ai_provider_connection_contract.toml](../../set/contracts/ai_provider_connection_contract.toml)
- Flows: [ai_provider_setup_flow.md](../flows/ai_provider_setup_flow.md), [onboarding_session_flow.md](../flows/onboarding_session_flow.md)
