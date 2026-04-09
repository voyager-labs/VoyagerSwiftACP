# Complete Provider OAuth Connection

## Metadata

| Field            | Value                                                                                |
| ---------------- | ------------------------------------------------------------------------------------ |
| Interaction ID   | SET-007-complete_provider_oauth_connection                                           |
| Interaction Type | background                                                                           |
| Feature          | Manage AI Connections                                                                |
| Category Key     | SET                                                                                  |
| Feature ID       | SET-007                                                                              |
| Status           | 드래프트                                                                             |
| Summary          | <<AI>> OAuth 인증 결과를 수신해 연결 성공·실패 상태를 저장하고 상태 영역을 갱신한다. |
| Related Region   | settings_window.settings_body.tab_ai.provider_status_area                            |
| Menu             | -                                                                                    |
| Shortcut         | -                                                                                    |

## Intent

- 사용자가 외부 인증을 완료했을 때, 결과를 신뢰성 있게 받아 앱 내 연결 상태로 반영하기 위해
  필요하다.
- 인증 성공/실패를 사용자에게 즉시 알리고 다음 액션을 정확하게 안내한다.

## Trigger / Entry Points

- OAuth 공급자 콜백 URL 또는 인증 토큰 전달 채널을 통해 결과가 유입될 때 호출된다.
- 설정 창에서 OAuth를 시작한 상태로 앱이 백그라운드에 있다가 복귀한 경우, 완료 판정 시점에 호출될 수
  있다.

## Preconditions

- 현재 세션에 OAuth 진행 중인 provider pending context가 존재해야 한다.
- 콜백 요청(또는 전달 토큰)을 검증할 수 있는 최소 메타데이터가 전달되어야 한다.
- Settings 창이 열려 있거나, 앱이 복귀했을 때 상태 갱신을 위한 표시 컨텍스트가 필요하다.

## Expected Outcome

- OAuth 결과가 정상일 경우 해당 provider가 연결됨 상태로 전환되어야 한다.
- OAuth 결과가 실패일 경우 오류 메시지와 재시도 경로가 표시되어야 한다.
- 어떤 경우든 연결 상태 영역은 최신 상태를 반영해야 한다.

## State Changes

- pending OAuth 상태가 완료 상태로 이동한다.
- 연결 토큰(또는 session reference)을 영속 저장소에 저장/갱신한다.
- provider 상태 배지와 연결 방식 라벨이 `연결됨` 또는 `오류`로 갱신된다.
- 연결 대상 provider의 마지막 검사 시각을 갱신한다.

## User-visible Feedback

- OAuth 완료/실패 결과를 반영한 토스트 또는 상태 메시지를 표시한다.
- 성공 시 사용자 입력 중단이 풀리고 연결 액션이 `재연결`/`해제`로 전환된다.
- 실패 시 “다시 시도”, “지원되는 계정으로 재로그인” 등의 후속 CTA를 제공한다.
- 인증 흐름이 오래 걸릴 때는 처리 중 표시를 유지한다.

## Edge Cases / Failure Handling

- 콜백이 오기 전에 앱이 강제 종료된 경우, 앱 복귀 시 pending context가 없는 상태에서 강제 오류로
  처리하지 않고 상태 복원 시도로 되돌린다.
- OAuth 토큰 교환이 실패하면 저장되지 않은 상태로 유지하고 오류 원인을 구분해 보여준다.
- 위조되거나 오래된 콜백 값은 무시하고 새로고침 가능한 실패 상태로 처리한다.
- 사용자 측에서 연결 창을 닫았거나 허용을 취소한 경우, 성공 상태로 오해되지 않도록 실패 상태로
  반영한다.
- 동일 provider에 대한 중복 콜백이 들어오면 첫 완료 결과만 반영하고 나머지는 무시한다.

## Acceptance Criteria

- [ ] OAuth 진행 중인 provider가 있고 인증 콜백을 수신한 상황에서, 연결 완료가 유효하면 상태 영역이
      `연결됨`으로 갱신되어야 한다.
- [ ] OAuth 인증이 실패한 상황에서, 수신 결과를 처리하면 사용자에게 실패 원인(또는 카테고리)과
      재시도 가능 경로가 표시되어야 한다.
- [ ] 토큰 교환이 실패한 상황에서, 저장소에 이전 연결 정보가 남아 있다면, 자동으로 새 자격으로
      덮어쓰지 않고 오류 상태가 유지되어야 한다.
- [ ] 잘못된/만료된 콜백에 대해서, 앱은 강제 성공 처리하지 않고 보류 또는 재인증 상태로 안내해야
      한다.
- [ ] OAuth 완료 처리와 동시에 설정 화면이 닫혀 있더라도, 사용자 진입 시 provider 상태는 최신 값으로
      복원되어야 한다.

## Permissions / Dependencies

- 네트워크 연결이 필요하다.
- OAuth provider별 토큰 교환 API 접근이 가능해야 한다.
- pending OAuth context와 callback correlation 정보를 안전하게 식별할 수 있어야 한다.
- 완료 후 상태 반영은 `SET-007-show_ai_provider_status`와 연동된다.

## Observability / Analytics

- OAuth 콜백 수신 성공/실패
- 토큰 교환 성공률
- pending context 만료/중복 콜백
- OAuth 완료 후 상태 갱신 반영 지연

## Related Interactions

- [SET-007-start_provider_oauth_connection](SET-007-start_provider_oauth_connection.md)
- [SET-007-show_ai_provider_status](SET-007-show_ai_provider_status.md)
- [SET-007-restore_ai_provider_connection_status](SET-007-restore_ai_provider_connection_status.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `243`
