---
interaction_id: "SET-007-show_ai_provider_status"
interaction_type: "display"
feature: "Manage AI Connections"
category_key: "SET"
feature_id: "SET-007"
status: "드래프트"
summary: "<<AI>> 현재 빌드에서 지원되는 provider 중 사용자가 선택한 provider의 현재 연결 상태와 사용 가능 여부를 상태 배지·문구로 표시한다."
related_region: "settings_window.settings_body.tab_ai.provider_status_area"
menu: "-"
shortcut: "-"
---

# Show AI Provider Status

## Intent

- 사용자가 현재 선택한 provider가 실제로 사용 가능한 상태인지 즉시 판단할 수 있게 한다.
- 미연결 / 검증 중 / 연결됨 / 오류 / 재연결 필요 상태마다 다음 행동을 이해할 수 있게 한다.

## Trigger / Entry Points

- Settings 창의 AI 탭이 표시될 때 상태 영역을 렌더링하며 호출된다.
- 사용자가 provider를 바꿀 때 해당 provider 기준 상태를 다시 표시한다.
- OAuth 완료, API key 검증, 연결 해제, 상태 복원 이후 후속 표시 단계로 호출된다.

## Preconditions

- Settings 창이 열려 있고 AI 탭이 표시된 상태
- 상태를 표시할 대상 provider가 선택된 상태
- 현재 연결 상태 스냅샷이 있거나, 직전 상태 조회 결과가 반영 가능한 상태

## Expected Outcome

- 사용자는 현재 provider의 연결 가능 상태를 한 눈에 이해할 수 있어야 한다.
- 상태에 따라 적절한 다음 행동(연결 시작, 재시도, 재연결, 해제)이 함께 노출되어야 한다.
- 상태를 아직 확정할 수 없는 경우에도 `알 수 없음` 또는 `확인 중`으로 구분되어야 한다.

## State Changes

- 선택된 provider의 내부 연결 상태가 사용자에게 보이는 상태 배지와 안내 문구로 변환된다.
- 상태 영역의 CTA가 현재 상태에 맞게 갱신된다.
- 최소한 아래 가시 상태 중 하나로 표현된다.
    - 미연결
    - 검증 필요
    - 연결 중 / 확인 중
    - 연결됨
    - 오류
    - 재연결 필요

## User-visible Feedback

- 상태 배지와 요약 문구를 표시한다.
- 현재 상태의 의미와 제한 사항을 짧게 설명한다.
- 필요한 경우 `OAuth로 연결`, `API key 확인`, `다시 시도`, `연결 해제` 같은 후속 액션을 노출한다.
- 마지막 확인 시점 또는 최신 상태 반영이 지연 중이라는 안내를 표시할 수 있다.

## Edge Cases / Failure Handling

- 아직 한 번도 연결을 시도하지 않은 provider는 오류가 아니라 `미연결`로 표시한다.
- 상태 확인이 진행 중이면 이전 성공 상태를 즉시 확정값처럼 보이지 않게 하고 `확인 중`으로 구분한다.
- 직전 연결은 있었지만 현재 자격이 만료되었으면 일반 오류가 아니라 `재연결 필요`로 구분한다.
- 상태 조회 자체가 실패하면 성공으로 단정하지 않고 `상태 확인 실패` 또는 재시도 안내를 표시한다.
- provider가 현재 빌드에서 특정 연결 방식을 지원하지 않으면 지원되지 않는 방식의 액션을 비활성 또는
  숨김 처리한다.

## Acceptance Criteria

- [ ] AI 탭에서 provider가 선택된 상황에서, 상태 영역이 렌더링되면, 해당 provider의 현재 연결 상태가
      식별 가능한 배지와 문구로 표시되어야 한다.
- [ ] 저장된 자격이 없고 아직 연결한 적이 없는 상황에서, 상태를 표시하면, 오류가 아니라 `미연결`
      상태로 표시되어야 한다.
- [ ] API key 또는 OAuth 검증이 진행 중인 상황에서, 상태를 표시하면, 완료 전까지 `연결 중` 또는
      `확인 중` 상태가 표시되어야 한다.
- [ ] 이전에는 연결되었지만 현재 자격이 만료된 상황에서, 상태를 표시하면, 일반 오류가 아니라
      `재연결 필요` 상태와 후속 액션이 표시되어야 한다.
- [ ] 상태 조회가 실패한 상황에서, 상태를 표시하면, 성공으로 오인될 수 있는 표시 대신 재시도 가능한
      오류 안내가 표시되어야 한다.

## Permissions / Dependencies

- provider별 저장된 연결 메타데이터 또는 최신 상태 조회 결과에 접근할 수 있어야 한다.
- 상태 표시 정확도는 `SET-007-restore_ai_provider_connection_status`,
  `SET-007-verify_provider_api_key`, `SET-007-complete_provider_oauth_connection`의 결과에 의존한다.

## Observability / Analytics

- 상태 영역 노출
- 표시된 상태 종류
- 상태별 CTA 노출
- 상태 조회 실패 표시
- 재연결 필요 상태 진입

## Related Interactions

- [SET-007-select_ai_provider](SET-007-select_ai_provider.md)
- [SET-007-restore_ai_provider_connection_status](SET-007-restore_ai_provider_connection_status.md)
- [SET-007-verify_provider_api_key](SET-007-verify_provider_api_key.md)
- [SET-007-complete_provider_oauth_connection](SET-007-complete_provider_oauth_connection.md)
- [SET-007-disconnect_ai_provider](SET-007-disconnect_ai_provider.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `240`
