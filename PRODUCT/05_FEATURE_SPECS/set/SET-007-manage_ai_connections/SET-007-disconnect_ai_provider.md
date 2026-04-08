# Disconnect AI Provider

## Metadata

| Field            | Value                                                                                                  |
| ---------------- | ------------------------------------------------------------------------------------------------------ |
| Interaction ID   | SET-007-disconnect_ai_provider                                                                         |
| Interaction Type | command                                                                                                |
| Feature          | Manage AI Connections                                                                                  |
| Category Key     | SET                                                                                                    |
| Feature ID       | SET-007                                                                                                |
| Status           | 드래프트                                                                                               |
| Summary          | <<AI>> 선택한 provider의 현재 연결을 해제하고 이후 채팅이 해당 연결을 사용하지 않도록 상태를 갱신한다. |
| Related Region   | settings_window.settings_body.tab_ai.provider_status_area                                              |
| Menu             | -                                                                                                      |
| Shortcut         | -                                                                                                      |

## Intent

- 사용자가 현재 provider의 연결을 명시적으로 종료하고, 이후 채팅에서 잘못된 provider가 사용되는 것을
  막고자 한다.
- 연결 정리를 통해 credential 오남용 위험을 줄이고 재설정 동선을 명확히 만든다.

## Trigger / Entry Points

- AI 탭 provider 상태 영역에서 `연결 해제` 액션을 선택할 때 호출된다.
- 연결 오류가 잦아 재설정이 필요한 상황에서 이 동작을 후속으로 사용한다.

## Preconditions

- 선택된 provider가 존재해야 한다.
- 해당 provider가 `연결됨` 또는 `부분 연결` 상태여야 한다.
- 사용자 확인이 필요한 정책이 있다면 확인 모달 또는 보조 단계가 허용되어야 한다.

## Expected Outcome

- 해당 provider의 active 연결 정보가 해제되어야 한다.
- 이후 채팅/요청에서 해당 provider 연결이 사용되지 않아야 한다.
- 상태 영역은 연결 해제된 상태로 바뀌고, 필요 시 다시 연결할 수 있는 안내가 노출되어야 한다.

## State Changes

- 저장된 access token/credential을 제거하거나 비활성화한다.
- provider 상태가 `미연결`로 바뀐다.
- 기본 채팅 provider 선택값이 해당 provider로 고정되어 있다면 fallback 규칙에 따라 안전한 상태로
  전환한다.
- 마지막 검증 시각, 마지막 오류/연결 기록은 감사용으로 유지하거나 규칙에 맞게 정리한다.

## User-visible Feedback

- 즉시 연결 해제 진행 중임을 표시한다.
- 성공 시 성공 메시지와 함께 상태 배지가 `미연결`로 갱신된다.
- 실패 시, 기존 연결은 유지/분리되지 않았음을 명확히 알리고 재시도 버튼을 제공한다.
- 연결 해제 후에 사용 가능한 provider나 API key 입력 경로를 이어서 안내한다.

## Edge Cases / Failure Handling

- 이미 미연결 상태를 다시 해제 요청할 경우, 중복 요청 에러 없이 현재 상태를 반복 확인해 `미연결`
  상태를 보존한다.
- 서버(혹은 토큰 폐기 API) 응답이 지연되면, 즉시 반영 가능한 상태와 완료 대기 상태를 분리해
  표시한다.
- 연결 해제 API가 실패하면 사용자에게 명시적으로 경고하고 재시도할 수 있게 한다.
- 앱 재시작 이전에 임시 캐시 상태만 반영된 경우 영속 해제까지 지연될 수 있으므로 복구 안내를
  표시한다.
- 현재 사용 중인 provider를 즉시 강제 해제해야 하는 정책이라면, 진행 중이던 요청은 실패 처리된 후
  실패 이유를 안내한다.

## Acceptance Criteria

- [ ] `연결됨` 상태인 provider에서 해제 액션을 호출하면, 설정 화면에서 `미연결` 상태로 바뀌고 사용
      중인 provider 목록에서 제외되어야 한다.
- [ ] 연결 해제 직후 즉시 채팅이나 요청에서 해당 provider credential이 사용되지 않아야 한다.
- [ ] 이미 해제된 provider에 대해 해제 액션을 호출한 경우, 시스템은 오류를 내지 않고 현재 미연결
      상태를 유지해야 한다.
- [ ] 해제 API 또는 토큰 폐기 과정이 실패한 경우, 기존 연결이 유지되었는지 또는 영구 해제가 완료되지
      않았는지 명확하게 안내되어야 한다.
- [ ] 연결 해제 이후 사용자가 다시 연결을 시도하면, 새 연결 시작 흐름으로 정상 진입해야 한다.

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

- [SET-007-restore_ai_provider_connection_status](SET-007-restore_ai_provider_connection_status.md)
- [SET-007-show_ai_provider_status](SET-007-show_ai_provider_status.md)
- [SET-007-start_provider_oauth_connection](SET-007-start_provider_oauth_connection.md)
- [SET-007-enter_provider_api_key](SET-007-enter_provider_api_key.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `244`
- Writing guide: `../../../../META/feature_specs_writing.md`
- Template: `../../template.md`
