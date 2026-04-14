---
interaction_id: "SET-007-restore_ai_provider_connection_status"
interaction_type: "background"
feature: "Manage AI Connections"
category_key: "SET"
feature_id: "SET-007"
status: "드래프트"
summary: "<<AI>> 앱 재실행 또는 설정 진입 시 저장된 provider connection 상태를 복원·재확인해 provider 목록 row의 상태와 액션을 갱신한다."
related_region: "settings_window.settings_body.tab_ai.provider_list_area"
menu: "-"
shortcut: "-"
---

# Restore AI Provider Connection Status

## Intent

- 앱 재실행·복귀 시에도 AI 연동 상태가 흔들리지 않도록 복원한다.
- 저장 데이터와 실제 유효 상태를 비교해 사용자가 목록 row에서 신뢰 가능한 상태 표시를 보게 한다.

## Trigger / Entry Points

- 앱 기동 완료 후 또는 AI 탭 진입 시 자동으로 호출될 수 있다.
- 설정 화면이 재활성화되거나 앱이 포그라운드로 복귀했을 때 실행될 수 있다.

## Preconditions

- provider catalog와 비교할 수 있는 최소한 하나 이상의 provider 설정 또는 자격정보 저장 기록이 존재해야 한다.
- 해당 provider의 상태 조회 API/체크 절차에 접근할 수 있어야 한다.
- provider 목록 row 상태를 계산할 수 있는 컨텍스트가 필요하다.

## Expected Outcome

- 저장된 연결 정보와 실제 유효성 기준에 따라 각 provider row 상태가 `Connected`/`Failed`/`Not verified` 중 하나로 정합성 있게 표시되어야 한다.
- 오래된 캐시가 살아있더라도 사용자에게 최신 동작을 보장하도록 보정되어야 한다.

## State Changes

- 앱 또는 화면 진입 시점의 provider 상태 캐시가 갱신된다.
- 유효한 token/credential은 `Connected`로 표시되고, 만료된 credential은 `Failed`로 변경된다.
- 상태 재확인 결과를 기반으로 provider별 row CTA(`Connect`/`Disconnect`/`Reconnect`)가 갱신된다.
- 마지막으로 사용한 provider 기억값이 여전히 유효하면 내부 상태로만 유지하고, 유효하지 않으면 기억값을 정리한다.

## User-visible Feedback

- 로딩 중 row 단위 배지 또는 `Checking status...` 메시지를 표시한다.
- 복원 완료 후 목록 row 상태를 최종 상태로 갱신한다.
- 개별 provider별 유효성 결과를 목록 row에 표시한다.
- 마지막으로 사용한 provider가 있더라도 default 설정 UI나 `Last used` 보조 표시는 노출하지 않는다.
- 복원 실패 또는 만료 상태는 row의 실패 아이콘/배지로 우선 표현하고, 긴 실패 문구는 기본 노출하지 않아도 된다.

## Edge Cases / Failure Handling

- 저장된 자격정보가 손상된 경우, 즉시 `Failed`로 처리하고 재연결 가이드를 제공한다.
- 네트워크/인증 서비스 장애로 조회를 못할 때는 성공으로 단정하지 않고 `Failed` 상태와 재확인 경로를 표시한다.
- 일부 provider만 조회 실패하면 성공 provider는 `Connected`로, 실패 provider는 `Failed`로 각각 표시한다.
- 조회 결과가 갑자기 서로 다른 provider로 엇갈리면 최근 타임스탬프/우선순위를 기준으로 동기화한다.
- 대량 provider 조회가 길어질 때는 상태 갱신의 진행 중 안내를 지속한다.
- 복원 실패의 원인은 내부적으로 기록하되, 기본 UI에서는 row 실패 아이콘/배지와 재시도 액션만으로 충분할 수 있다.
- 마지막으로 사용한 provider가 더 이상 연결 가능하지 않으면 해당 기억값은 정리하고 다른 provider를 자동 지정하지 않는다.

## Acceptance Criteria

- [ ] 앱 재실행 후 AI 탭 진입 시, 저장된 provider 연결 정보가 로드되어 provider 목록 row 상태에 반영되어야 한다.
- [ ] 저장된 토큰이 만료된 provider는 재확인 후 `Failed`로 갱신되고 reconnect 경로가 제공되어야 한다.
- [ ] 네트워크 장애가 발생한 상황에서 복원 동작을 실행하면, 성공 상태를 임의로 가정하지 않고 `Failed` 또는 재확인 안내가 표시되어야 한다.
- [ ] 일부 provider 상태 조회가 실패하더라도, 다른 provider는 기존 정상 상태를 유지한 채 부분 실패로 표시되어야 한다.
- [ ] 상태 복원 작업이 완료되면, 사용자 화면에서 각 provider row의 status badge와 후속 액션이 일관된 상태로 렌더링되어야 한다.
- [ ] 마지막으로 사용한 provider가 유효한 상태에서 복원되더라도, `Last used` 보조 표시는 노출되지 않아야 하며 별도 active/default 설정 UI는 보이지 않아야 한다.
- [ ] 복원 실패가 발생한 row는 긴 오류 문구 대신 실패 아이콘/배지와 재시도 액션만 노출해도 충분해야 한다.

## Permissions / Dependencies

- 저장된 provider credential 접근 권한이 필요하다.
- provider별 상태 조회 API 또는 검증 채널이 필요하다.
- 앱 기동 이벤트 또는 화면 진입 이벤트를 트리거로 받을 수 있어야 한다.

## Observability / Analytics

- 복원 실행 빈도
- provider별 조회 성공/실패 비율
- `Checking status...` 진입 빈도
- 복원 후 최종 상태 분포(`Connected`/`Not verified`/`Failed`)

## Related Interactions

- [SET-007-connect_ai_provider](SET-007-connect_ai_provider.md)
- [SET-007-disconnect_ai_provider](SET-007-disconnect_ai_provider.md)
- [SET-007-show_ai_provider_list](SET-007-show_ai_provider_list.md)
## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `258`
