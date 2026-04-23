---
interaction_id: "SET-007-show_ai_provider_list"
interaction_type: "display"
feature: "Manage AI Connections"
category_key: "SET"
feature_id: "SET-007"
status: "기획 완료"
summary: "현재 빌드에서 지원되는 프로바이더 카탈로그를 표시하고, 각 프로바이더 항목에 연결 상태, 지원 연결 방식, 기본 동작(연결/연결 해제)을 함께 보여준다."
related_region: "settings_window.settings_body.tab_ai.provider_list_area"
menu: "-"
shortcut: "-"
---

# Show AI Provider List

## Intent

- 사용자가 Settings AI 탭에서 현재 빌드 기준 `provider_catalog`를 빠르게 확인하고, 각 `provider` row에서 연결 상태와 다음 액션을 판단할 수 있게 한다.
- provider 연결 관리를 row 단위로 수행하게 하되, 별도의 default provider 선택 UI는 노출하지 않는다.

## Trigger / Entry Points

- Settings 창의 AI 탭이 열릴 때 provider 목록 영역을 렌더링하며 호출된다.
- [SET-007-restore_ai_provider_connection_status](SET-007-restore_ai_provider_connection_status.md)가 row status를 갱신한 직후 목록을 다시 표시할 때 호출된다.
- 현재 빌드의 provider 정보가 바뀌어 목록 표시 정보를 다시 계산해야 할 때 호출된다.

## Preconditions

- Settings 창이 열려 있고 AI 탭이 표시된 상태여야 한다.
- 현재 빌드 기준 `provider_catalog` 정보가 준비되어야 한다.
- 각 row의 현재 status를 계산할 수 있도록 저장된 연결 정보 또는 그 부재가 판정 가능해야 한다.

## Expected Outcome

- `provider_catalog`의 각 row는 `checking_status`, `connected`, `not_verified`, `connect_in_progress`, `disconnect_in_progress`, `connection_failed`, `unavailable` 중 하나의 status로 계산되어야 한다.
- 각 `provider` row에는 이름, 지원 연결 방식, 현재 status badge, primary action이 함께 표시되어야 한다.
- primary action은 row status에 따라 `Connect`, `Disconnect`, `Reconnect` 또는 비활성화 상태로 계산되어야 한다.
- `connected` row는 목록에서 사라지지 않고 같은 row 안에서 status와 primary action만 갱신되어야 한다.
- default provider 설정 UI와 `Last used` 보조 표시는 노출하지 않아야 한다.

## State Changes

- `provider_catalog`와 저장된 연결 정보가 목록 표시 정보로 결합된다.
- 각 row의 primary action은 `not_verified`면 `Connect`, `connected`면 `Disconnect`, `connection_failed`면 `Reconnect`로 계산된다.
- `connect_in_progress`와 `disconnect_in_progress` row는 같은 위치에서 진행 중 표시와 비활성화된 action 상태를 유지해야 한다.
- `unavailable` row는 현재 빌드에서 연결 가능한 row처럼 동작하면 안 되며, action은 비활성화되거나 제거되어야 한다.
- 마지막으로 실제 요청에 사용된 provider 기억값은 내부 상태로만 유지하고, 목록 시각 표현에는 직접 노출하지 않는다.

## User-visible Feedback

- 각 row는 provider 이름과 지원 연결 방식 정보를 함께 보여줘야 한다.
- `checking_status` row는 spinner 또는 `Checking status...` 피드백을 보여줘야 한다.
- `connected` row는 `Disconnect` action과 함께 안정적인 연결 상태를 보여줘야 한다.
- `not_verified` row는 `Connect` 진입점을 바로 노출해야 한다.
- `connection_failed` row는 긴 오류 문구 대신 failure badge와 `Reconnect` action을 우선 노출해야 한다.
- `unavailable` row는 `Unavailable in this build` 안내를 보여주고 정상 연결 가능한 row처럼 보이면 안 된다.

## Edge Cases / Failure Handling

- `provider_catalog` 로딩에 실패하면 빈 목록 대신 실패 안내와 재시도 action을 보여줘야 한다.
- 일부 row만 status 복원에 실패하더라도 목록 전체 렌더링은 유지하고, 실패 row만 `connection_failed`로 표시해야 한다.
- 저장된 연결 정보가 있어도 현재 빌드에서 그 row가 `unavailable`이면 `connected`처럼 보이게 하면 안 된다.
- 마지막으로 사용한 provider 기억값이 남아 있어도 목록은 해당 row를 default처럼 강조하거나 자동 선택하지 않아야 한다.
- 실패 사유는 row에 긴 텍스트로 누적하지 않고 status badge와 primary action 중심으로 표현해야 한다.

## Acceptance Criteria

- [ ] AI 탭이 열린 상황에서, 목록을 표시하면, 현재 빌드에서 지원되는 provider만 보여야 한다.
- [ ] provider 목록을 표시한 상황에서, 각 row를 보면, provider 이름, 지원 연결 방식, 현재 status badge, primary action이 함께 보여야 한다.
- [ ] `connected` row가 있는 상황에서, 목록을 다시 표시하면, 해당 row는 제거되지 않고 status badge와 primary action만 갱신되어야 한다.
- [ ] `connection_failed` row가 있는 상황에서, 목록을 표시하면, 해당 row에는 failure badge와 `Reconnect` action이 표시되어야 한다.
- [ ] `unavailable` row가 있는 상황에서, 목록을 표시하면, 해당 row는 `Unavailable in this build` 안내를 보여주고 정상 연결 action을 노출하지 않아야 한다.
- [ ] `provider_catalog` 로딩에 실패한 상황에서, 목록을 표시하면, 빈 화면 대신 실패 안내와 재시도 action이 제공되어야 한다.
- [ ] 마지막으로 사용한 provider가 기록되어 있는 상황에서, 목록을 표시하더라도, default provider 설정 UI나 `Last used` 보조 표시는 노출되지 않아야 한다.

## Permissions / Dependencies

- 현재 빌드에서 지원되는 `provider_catalog` 정보가 필요하다.
- row별 status 계산은 [SET-007-restore_ai_provider_connection_status](SET-007-restore_ai_provider_connection_status.md)의 결과에 의존한다.
- status vocabulary와 primary action 정책은 [ai_provider_connection_contract.toml](../contracts/ai_provider_connection_contract.toml)을 따른다.

## Observability / Analytics

- provider 목록 노출
- row별 primary action 노출 비율
- `provider_catalog` 로드 실패
- row status 분포(`connected`, `not_verified`, `connection_failed`, `unavailable`)

## Related Interactions

- [SET-007-connect_ai_provider](SET-007-connect_ai_provider.md)
- [SET-007-disconnect_ai_provider](SET-007-disconnect_ai_provider.md)
- [SET-007-restore_ai_provider_connection_status](SET-007-restore_ai_provider_connection_status.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:241`
- Contracts: [ai_provider_connection_contract.toml](../contracts/ai_provider_connection_contract.toml)
- Flows: [ai_provider_connection_flow.md](../flows/ai_provider_connection_flow.md)
