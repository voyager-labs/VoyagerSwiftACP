---
interaction_id: "SET-007-connect_ai_provider"
interaction_type: "command"
feature: "Manage AI Connections"
category_key: "SET"
feature_id: "SET-007"
status: "드래프트"
summary: "<<AI>> provider 목록 row의 `Connect` 액션을 실행한다. 현재 빌드에서는 ChatGPT Codex는 OAuth flow를 시작하고, OpenAI는 같은 row 문맥에서 API key 제출을 요구한다."
related_region: "settings_window.settings_body.tab_ai.provider_list_area"
menu: "-"
shortcut: "-"
---

# Connect AI Provider

## Intent

- 사용자가 provider마다 다른 인증 방식을 신경 쓰지 않고 동일한 `Connect` 진입점으로 연결을 시작할 수 있게 한다.
- provider를 하나의 연결 객체로 다루되, 내부적으로는 provider가 허용하는 연결 방식으로 자연스럽게 분기시킨다.

## Trigger / Entry Points

- provider 목록 row의 `Connect` 버튼을 선택할 때 호출된다.

## Preconditions

- 연결할 provider가 row action으로 명확히 지정되어야 한다.
- 대상 provider가 현재 빌드에서 지원되는 상태여야 한다.
- 대상 provider가 이미 연결 중이 아니어야 하며, 재연결 정책이 있다면 재시작 가능한 상태여야 한다.

## Expected Outcome

- `ChatGPT Codex`에 대해 connect를 호출하면 OAuth 연결 흐름으로 진입해야 한다.
- `OpenAI`에 대해 connect를 호출하면 같은 row 문맥에서 API key 제출을 요구하는 inline 연결 흐름으로 진입해야 한다.
- 사용자는 연결 방식을 고르기보다 provider를 연결한다는 동일한 mental model을 유지해야 한다.
- 이 기능은 explicit active/default provider를 설정하지 않으며, 실제 런타임에서 마지막으로 사용한 provider 기억은 내부 상태로만 유지되어야 한다.

## State Changes

- provider connection object에 대해 새로운 연결 시도가 시작된다.
- OAuth provider는 외부 인증으로 이어지는 pending 연결 상태를 생성한다.
- API key provider는 같은 row 문맥 안에서 credential 제출을 요구하는 입력 상태로 전환된다.
- row의 상태 배지와 액션은 connect 진행 상황에 맞게 갱신될 수 있다.

## User-visible Feedback

- connect 액션 직후 시스템은 어떤 provider를 어떤 방식으로 연결하는지 row 문맥에서 명확히 알려준다.
- OAuth provider는 브라우저 인증 진입 안내를 보여준다.
- API key provider는 별도 상세 패널 없이 같은 row 안의 inline field와 제출 액션으로 key 입력을 요구한다.
- 이미 연결된 provider에는 `Connect` 대신 현재 상태 또는 관리 액션이 우선 노출되어야 한다.
- 같은 row에서 연결 진행 중일 때는 중복 클릭을 막기 위해 버튼 비활성화 또는 spinner 상태를 보여줘야 한다.
- 연결이 실패하면 결과는 즉시 row 상태에 반영하되, 긴 실패 문구 대신 실패 아이콘/배지와 `Retry` 액션만 우선 노출한다.

## Edge Cases / Failure Handling

- 이미 연결된 provider에 대해 connect를 다시 호출하면 중복 연결을 만들지 않고 상태 보기 또는 재연결 경로로 유도한다.
- 현재 빌드에서 지원되지 않는 provider에는 connect 액션을 노출하지 않거나 비활성화한다.
- provider 메타데이터가 손상되어 연결 방식을 결정할 수 없으면 연결을 시작하지 않고 오류 안내를 표시한다.
- connect 직후 사용자가 다른 row를 조작해도 기존 시도는 독립적인 provider connection object 기준으로 관리되어야 한다.
- API key 제출 또는 OAuth 연결이 실패하면 row는 즉시 실패 상태로 전환되어야 하지만, 실패 사유는 긴 텍스트 대신 아이콘/배지 수준으로 축약해도 된다.

## Acceptance Criteria

- [ ] provider 목록에서 `ChatGPT Codex` row의 `Connect`를 누르면 OAuth 연결 흐름으로 진입해야 한다.
- [ ] provider 목록에서 `OpenAI` row의 `Connect`를 누르면 같은 row 안의 inline field로 API key 제출을 요구하는 연결 흐름으로 진입해야 한다.
- [ ] 이미 연결된 provider는 목록에서 사라지지 않고, `Connect` 대신 현재 상태 또는 관리 액션이 노출되어야 한다.
- [ ] 연결 방식을 결정할 수 없는 provider에 대해 connect를 호출하면, 연결을 시작하지 않고 실패 안내가 표시되어야 한다.
- [ ] 같은 provider row가 이미 연결 진행 중인 상태에서 `Connect`를 다시 누르면, 중복 연결 시도를 만들지 않고 진행 중 표시만 유지해야 한다.
- [ ] provider 연결이 실패한 경우, row는 즉시 실패 아이콘/배지와 `Retry` 액션을 보여줘야 하며 긴 실패 사유 텍스트를 반드시 노출할 필요는 없다.

## Permissions / Dependencies

- provider별 연결 방식 메타데이터가 필요하다.
- OAuth와 API key 분기는 모두 별도 제품 interaction으로 분리하지 않고 connect flow 내부에서 처리한다.

## Observability / Analytics

- provider별 connect 시도
- provider별 연결 방식 분기 결과
- connect 이후 provider별 연결 성공률
- 이미 연결된 provider에 대한 중복 connect 시도

## Related Interactions

- [SET-007-disconnect_ai_provider](SET-007-disconnect_ai_provider.md)
- [SET-007-restore_ai_provider_connection_status](SET-007-restore_ai_provider_connection_status.md)
- [SET-007-show_ai_provider_list](SET-007-show_ai_provider_list.md)
## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `256`
