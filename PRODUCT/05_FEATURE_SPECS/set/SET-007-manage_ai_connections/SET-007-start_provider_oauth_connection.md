# Start Provider OAuth Connection

## Metadata

| Field            | Value                                                                                  |
| ---------------- | -------------------------------------------------------------------------------------- |
| Interaction ID   | SET-007-start_provider_oauth_connection                                                |
| Interaction Type | command                                                                                |
| Feature          | Manage AI Connections                                                                  |
| Category Key     | SET                                                                                    |
| Feature ID       | SET-007                                                                                |
| Status           | 드래프트                                                                               |
| Summary          | <<AI>> 선택한 provider의 OAuth 연결 절차를 시작하고, 외부 인증 플로우 진입을 준비한다. |
| Related Region   | settings_window.settings_body.tab_ai.provider_connection_area                          |
| Menu             | -                                                                                      |
| Shortcut         | -                                                                                      |

## Intent

- 사용자가 provider 계정 인증을 앱 안에서 시작할 수 있게 한다.
- 인증 시작 시점부터 UI가 `연결 시도 중` 문맥으로 전환되도록 한다.

## Trigger / Entry Points

- AI 탭의 연결 영역에서 `OAuth로 연결` 또는 동등한 CTA를 선택하면 호출된다.
- 미연결, 오류, 재연결 필요 상태에서 후속 행동으로 진입한다.

## Preconditions

- Settings 창이 열려 있고 AI 탭이 표시된 상태
- OAuth를 지원하는 provider가 선택된 상태
- 동일 provider에 대한 OAuth 완료 대기 세션이 없거나 재시작 가능한 상태

## Expected Outcome

- 사용자는 외부 인증 플로우로 진입할 수 있어야 한다.
- 인증이 완료되기 전까지 현재 provider는 `OAuth 진행 중` 또는 동등한 임시 상태로 표시되어야 한다.
- 앱은 완료 결과를 수신할 수 있는 pending 연결 문맥을 유지해야 한다.

## State Changes

- 선택한 provider에 대한 pending OAuth 시도가 생성된다.
- 상태 영역이 `연결 중` 또는 `브라우저에서 승인 대기 중` 상태로 바뀐다.
- 콜백 수신에 필요한 일시 세션 정보 또는 request context가 저장된다.

## User-visible Feedback

- 외부 인증이 열리는 동안 로딩 또는 진행 중 안내를 표시한다.
- 시스템 브라우저 또는 인증 창이 열렸다는 사실을 사용자에게 알린다.
- 사용자가 인증 후 돌아와야 한다는 안내를 표시할 수 있다.

## Edge Cases / Failure Handling

- 시스템 브라우저 또는 인증 창을 열지 못하면, 즉시 실패 안내와 재시도 액션을 제공한다.
- 동일 provider에 대한 OAuth 시도가 이미 진행 중이면, 새 시도를 중복으로 만들지 않고 기존 진행
  상태를 안내한다.
- 네트워크가 없으면 브라우저 열기 전 또는 직후에 연결 불가 안내를 표시한다.
- provider가 현재 세션에서 OAuth를 더 이상 지원하지 않으면, 시작 대신 비지원 안내를 표시한다.

## Acceptance Criteria

- [ ] OAuth를 지원하는 provider가 선택된 상황에서, 사용자가 OAuth 연결 시작을 호출하면, 외부 인증
      플로우로 진입할 수 있는 상태가 시작되어야 한다.
- [ ] OAuth 시작이 정상적으로 접수된 상황에서, 사용자가 AI 탭을 보면, 상태 영역에 `연결 중` 또는
      동등한 진행 상태가 표시되어야 한다.
- [ ] 동일 provider에 대한 OAuth가 이미 진행 중인 상황에서, 사용자가 다시 시작을 호출하면, 중복
      pending 세션이 생성되지 않아야 한다.
- [ ] 시스템 브라우저 또는 인증 창을 열 수 없는 상황에서, 사용자가 시작을 호출하면, 실패 안내와
      재시도 가능한 행동이 표시되어야 한다.

## Permissions / Dependencies

- 네트워크 연결이 필요하다.
- provider별 OAuth 시작 endpoint 또는 인증 URL 메타데이터가 필요하다.
- 시스템 브라우저 또는 인증용 외부 창을 열 수 있어야 한다.
- 결과 수신은 `SET-007-complete_provider_oauth_connection`에 의존한다.

## Observability / Analytics

- OAuth 시작 시도
- 외부 인증 창 열기 성공 / 실패
- 중복 시작 차단
- provider별 OAuth 시작량

## Related Interactions

- [SET-007-complete_provider_oauth_connection](SET-007-complete_provider_oauth_connection.md)
- [SET-007-show_ai_provider_status](SET-007-show_ai_provider_status.md)
- [SET-007-select_ai_provider](SET-007-select_ai_provider.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `242`
