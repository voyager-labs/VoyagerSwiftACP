---
interaction_id: "SET-007-disconnect_ai_provider"
interaction_type: "command"
feature: "Manage AI Connections"
category_key: "SET"
feature_id: "SET-007"
status: "드래프트"
summary: "<<AI>> provider 목록 row의 `Disconnect` 액션을 실행해 해당 provider connection을 해제하고 이후 요청에서 해당 provider credential이 사용되지 않도록 상태를 갱신한다."
related_region: "settings_window.settings_body.tab_ai.provider_list_area"
menu: "-"
shortcut: "-"
---

# Disconnect AI Provider

## Intent

- 사용자가 현재 provider의 연결을 명시적으로 종료하고, 이후 요청에서 잘못된 provider가 사용되는 것을 막고자 한다.
- 연결 정리를 통해 credential 오남용 위험을 줄이고 재연결 동선을 명확히 만든다.

## Trigger / Entry Points

- AI 탭 provider 목록 row에서 `Disconnect` 액션을 선택할 때 호출된다.

## Preconditions

- 대상 provider가 row action으로 명확히 지정되어야 한다.
- 해당 provider가 `Connected` 상태이거나 active credential을 가진 상태여야 한다.
- 연결 해제 전 사용자 확인 모달을 표시할 수 있어야 한다.

## Expected Outcome

- 해당 provider의 active 연결 정보가 해제되어야 한다.
- 이후 요청에서 해당 provider 연결이 사용되지 않아야 한다.
- 해당 provider row는 연결 해제된 상태로 바뀌고, 필요 시 다시 연결할 수 있는 안내가 노출되어야 한다.

## State Changes

- 저장된 access token/credential을 제거하거나 비활성화한다.
- provider 상태가 `Not verified`로 바뀐다.
- 마지막으로 사용한 provider 기억값이 해당 provider를 가리키고 있었다면, 해당 기억값을 제거하거나 무효화한다.
- 마지막 검증 시각, 마지막 오류/연결 기록은 감사용으로 유지하거나 규칙에 맞게 정리한다.

## User-visible Feedback

- 사용자가 `Disconnect`를 누르면 먼저 확인 모달을 보여주고, 확인 이후에만 연결 해제 진행 중임을 표시한다.
- 성공 시 성공 메시지와 함께 row 상태 배지가 `Not verified`로 갱신된다.
- 실패 시, 기존 연결은 유지/분리되지 않았음을 명확히 알리고 재시도 버튼을 제공한다.
- 연결 해제 후에 사용 가능한 provider reconnect 경로를 이어서 안내한다.
- 해제된 provider가 마지막으로 사용한 provider였다면, 해당 내부 기억값은 제거되거나 무효화되어야 한다.

## Edge Cases / Failure Handling

- 이미 `Not verified` 상태를 다시 해제 요청할 경우, 중복 요청 에러 없이 현재 상태를 반복 확인해 `Not verified` 상태를 보존한다.
- 서버(혹은 토큰 폐기 API) 응답이 지연되면, 즉시 반영 가능한 상태와 완료 대기 상태를 분리해 표시한다.
- 연결 해제 API가 실패하면 사용자에게 명시적으로 경고하고 재시도할 수 있게 한다.
- 앱 재시작 이전에 임시 캐시 상태만 반영된 경우 영속 해제까지 지연될 수 있으므로 복구 안내를 표시한다.
- 현재 사용 중인 provider를 즉시 강제 해제해야 하는 정책이라면, 진행 중이던 요청은 실패 처리된 후 실패 이유를 안내한다.
- 사용자가 확인 모달에서 취소하면 실제 해제는 수행되지 않고 row 상태도 바뀌지 않아야 한다.

## Acceptance Criteria

- [ ] `Connected` 상태인 provider에서 해제 액션을 호출하면, 설정 화면에서 `Not verified` 상태로 바뀌고 provider row는 목록에 남아 있어야 한다.
- [ ] 연결 해제 직후 즉시 채팅이나 요청에서 해당 provider credential이 사용되지 않아야 한다.
- [ ] 이미 해제된 provider에 대해 해제 액션을 호출한 경우, 시스템은 오류를 내지 않고 현재 `Not verified` 상태를 유지해야 한다.
- [ ] 해제 API 또는 토큰 폐기 과정이 실패한 경우, 기존 연결이 유지되었는지 또는 영구 해제가 완료되지 않았는지 명확하게 안내되어야 한다.
- [ ] 연결 해제 이후 사용자가 다시 연결을 시도하면, 새 연결 시작 흐름으로 정상 진입해야 한다.
- [ ] 사용자가 확인 모달에서 연결 해제를 취소하면, 실제 해제는 실행되지 않고 row 상태도 유지되어야 한다.
- [ ] 마지막으로 사용한 provider를 해제한 경우, 해당 내부 기억값은 제거되거나 무효화되어야 하며 다른 provider가 자동으로 default 지정되지는 않아야 한다.

## Permissions / Dependencies

- provider별 credential 폐기/삭제 API 또는 로컬 저장소 쓰기 권한이 필요하다.
- 채팅/요청 파이프라인이 provider 변경 이벤트를 반영할 수 있어야 한다.
- 기본 provider fallback 정책이 정의되어 있어야 한다.

## Observability / Analytics

- 연결 해제 시도 횟수
- 연결 해제 성공/실패
- 해제 후 provider 재연결 성공률
- 해제 직후 채팅에서의 provider 사용 차단 이벤트

## Related Interactions

- [SET-007-connect_ai_provider](SET-007-connect_ai_provider.md)
- [SET-007-restore_ai_provider_connection_status](SET-007-restore_ai_provider_connection_status.md)
- [SET-007-show_ai_provider_list](SET-007-show_ai_provider_list.md)
## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `257`
