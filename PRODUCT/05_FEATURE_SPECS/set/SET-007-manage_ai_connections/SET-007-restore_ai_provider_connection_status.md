# Restore AI Provider Connection Status

## Metadata

| Field            | Value                                                                                                |
| ---------------- | ---------------------------------------------------------------------------------------------------- |
| Interaction ID   | SET-007-restore_ai_provider_connection_status                                                        |
| Interaction Type | background                                                                                           |
| Feature          | Manage AI Connections                                                                                |
| Category Key     | SET                                                                                                  |
| Feature ID       | SET-007                                                                                              |
| Status           | 드래프트                                                                                             |
| Summary          | <<AI>> 앱 재실행 또는 설정 진입 시 저장된 연결 정보를 바탕으로 provider 연결 상태를 복원·재확인한다. |
| Related Region   | settings_window.settings_body.tab_ai.provider_status_area                                            |
| Menu             | -                                                                                                    |
| Shortcut         | -                                                                                                    |

## Intent

- 앱 재실행·복귀 시에도 AI 연동 상태가 흔들리지 않도록 복원한다.
- 저장 데이터와 실제 유효 상태를 비교해 사용자가 신뢰 가능한 상태 표시를 보게 한다.

## Trigger / Entry Points

- 앱 기동 완료 후 또는 AI 탭 진입 시 자동으로 호출될 수 있다.
- 설정 화면이 재활성화되거나 앱이 포그라운드로 복귀했을 때 실행될 수 있다.

## Preconditions

- 최소한 하나 이상의 provider 설정 또는 자격정보 저장 기록이 존재해야 한다.
- 해당 provider의 상태 조회 API/체크 절차에 접근할 수 있어야 한다.
- 기본 provider 선택 값이 존재하는 경우, 상태 조회 대상 컨텍스트가 정해져야 한다.

## Expected Outcome

- 저장된 연결 정보와 실제 유효성 기준에 따라 UI 상태가 `연결됨`/`연결 실패`/`재연결 필요` 등으로
  정합성 있게 표시되어야 한다.
- 오래된 캐시가 살아있더라도 사용자에게 최신 동작을 보장하도록 보정되어야 한다.

## State Changes

- 앱 또는 화면 진입 시점의 provider 상태 캐시가 갱신된다.
- 유효한 토큰/credential은 정상 상태로 표시되고, 만료된 credential은 재확인 필요 상태로 변경된다.
- 상태 재확인 결과를 기반으로 provider별 후속 CTA(연결, 재연결, 키 입력)가 갱신된다.

## User-visible Feedback

- 로딩 중 배지 또는 미확인 상태 메시지를 표시한다.
- 복원 완료 후 상태 표시에 대해 최종 상태를 한 번에 갱신한다.
- 개별 provider별 유효성 결과를 리스트/상태 영역에 표시한다.

## Edge Cases / Failure Handling

- 저장된 자격정보가 손상된 경우, 즉시 `오류` 또는 `재설정 필요`로 처리하고 입력 가이드를 제공한다.
- 네트워크/인증 서비스 장애로 조회를 못할 때는 전체 실패가 아니라 `현재 확인 불가` 상태로 구분해
  표시한다.
- 일부 provider만 조회 실패하면 성공 provider는 정상으로, 실패 provider만 재확인 필요로 각각
  표시한다.
- 조회 결과가 갑자기 서로 다른 provider로 엇갈리면 최근 타임스탬프/우선순위를 기준으로 동기화한다.
- 대량 provider 조회가 길어질 때는 상태 갱신의 진행 중 안내를 지속한다.

## Acceptance Criteria

- [ ] 앱 재실행 후 AI 탭 진입 시, 저장된 provider 연결 정보가 로드되어 상태 영역에 표시되어야 한다.
- [ ] 저장된 토큰이 만료된 provider는 재확인 후 `재연결 필요` 또는 `연결되지 않음`으로 갱신되어야
      한다.
- [ ] 네트워크 장애가 발생한 상황에서 복원 동작을 실행하면, 성공 상태를 임의로 가정하지 않고
      `확인 실패` 또는 재확인 안내가 표시되어야 한다.
- [ ] 일부 provider 상태 조회가 실패하더라도, 다른 provider는 기존 정상 상태를 유지한 채 부분 실패로
      표시되어야 한다.
- [ ] 상태 복원 작업이 완료되면, 사용자 화면에서 status badge와 후속 액션이 일관된 상태로
      렌더링되어야 한다.

## Permissions / Dependencies

- 저장된 provider credential 접근 권한이 필요하다.
- provider별 상태 조회 API 또는 검증 채널이 필요하다.
- 앱 기동 이벤트 또는 화면 진입 이벤트를 트리거로 받을 수 있어야 한다.

## Observability / Analytics

- 복원 실행 빈도
- provider별 조회 성공/실패 비율
- `미확인 상태` 진입 빈도
- 복원 후 최종 상태 분포(연결됨/미연결/재연결)

## Related Interactions

- [SET-007-show_ai_provider_status](SET-007-show_ai_provider_status.md)
- [SET-007-complete_provider_oauth_connection](SET-007-complete_provider_oauth_connection.md)
- [SET-007-verify_provider_api_key](SET-007-verify_provider_api_key.md)
- [SET-007-disconnect_ai_provider](SET-007-disconnect_ai_provider.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `245`
- Writing guide: `../../../../META/feature_specs_writing.md`
- Template: `../../template.md`
