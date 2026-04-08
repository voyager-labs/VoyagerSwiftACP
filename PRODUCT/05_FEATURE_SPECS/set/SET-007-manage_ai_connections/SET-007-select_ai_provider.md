# Select AI Provider

## Metadata

| Field            | Value                                                                                                      |
| ---------------- | ---------------------------------------------------------------------------------------------------------- |
| Interaction ID   | SET-007-select_ai_provider                                                                                 |
| Interaction Type | command                                                                                                    |
| Feature          | Manage AI Connections                                                                                      |
| Category Key     | SET                                                                                                        |
| Feature ID       | SET-007                                                                                                    |
| Status           | 드래프트                                                                                                   |
| Summary          | <<AI>> 설정 가능한 외부 AI provider를 선택해 연결 상세 영역과 상태 영역을 해당 provider 기준으로 전환한다. |
| Related Region   | settings_window.settings_body.tab_ai.provider_list_area                                                    |
| Menu             | -                                                                                                          |
| Shortcut         | -                                                                                                          |

## Intent

- 사용자가 여러 provider 후보 중 지금 연결하거나 확인할 대상을 명확히 고를 수 있게 한다.
- 연결 입력 영역과 상태 영역이 항상 동일한 provider를 가리키도록 맞춘다.

## Trigger / Entry Points

- AI 탭의 provider 목록에서 특정 provider row/card를 선택할 때 호출된다.
- AI 탭 진입 시 마지막 선택 provider를 복원하는 후속 단계로 호출될 수 있다.

## Preconditions

- Settings 창이 열려 있고 AI 탭이 표시된 상태
- 선택 가능한 provider 목록이 로드된 상태

## Expected Outcome

- 현재 선택 provider가 명확히 전환되어야 한다.
- 연결 영역과 상태 영역은 새로 선택된 provider 기준 정보만 표시해야 한다.
- 사용 불가 또는 지원되지 않는 연결 방식은 해당 provider 문맥에서 구분되어야 한다.

## State Changes

- 현재 AI 설정 컨텍스트의 `selected provider`가 바뀐다.
- 연결 입력 폼, 사용 가능한 연결 방식, 상태 배지, 후속 액션이 새 provider 기준으로 다시 바인딩된다.
- 이전 provider에 대한 임시 표시 상태는 화면에서 내려가고, 새 provider의 저장/조회 가능한 상태가
  표시된다.

## User-visible Feedback

- 선택된 provider 항목이 시각적으로 강조된다.
- 연결 영역 제목, 설명, 버튼 문구가 선택된 provider 기준으로 바뀐다.
- 해당 provider가 OAuth만 지원하거나 API key만 지원하는 경우, 지원되지 않는 방식은 비노출 또는
  비활성화된다.

## Edge Cases / Failure Handling

- provider 목록이 비어 있으면 선택 대신 빈 상태 안내를 표시한다.
- 마지막으로 선택한 provider가 현재 빌드에서 더 이상 사용 불가하면, 기본 provider로 fallback 하거나
  선택 필요 상태를 표시한다.
- 연결 확인 또는 검증이 진행 중인 provider에서 다른 provider로 전환하면, 진행 중 작업을 묵시적으로
  성공 처리하지 않고 독립 상태로 유지하거나 전환 시 주의 안내를 표시한다.
- 선택한 provider의 상세 정보를 불러오지 못하면, 선택 강조는 유지하되 연결/상태 영역에 로딩 실패
  안내를 표시한다.

## Acceptance Criteria

- [ ] AI 탭에 둘 이상의 provider가 보이는 상황에서, 사용자가 다른 provider를 선택하면, 상태 영역과
      연결 영역이 새 provider 기준으로 갱신되어야 한다.
- [ ] 특정 provider가 선택된 상황에서, 사용자가 같은 provider를 다시 선택하면, 중복 선택으로 오류가
      발생하지 않아야 한다.
- [ ] 선택한 provider가 OAuth만 지원하는 상황에서, provider를 전환하면, API key 입력 액션은 노출되지
      않거나 비활성화되어야 한다.
- [ ] 선택한 provider의 상세 상태를 불러오지 못한 상황에서, provider를 선택하면, 연결/상태 영역에
      실패 안내와 재시도 가능한 표시가 제공되어야 한다.

## Permissions / Dependencies

- 현재 빌드에서 노출 가능한 provider 목록과 각 provider의 지원 연결 방식 메타데이터가 필요하다.
- 후속 상태 반영은 `SET-007-show_ai_provider_status`에 의존한다.

## Observability / Analytics

- provider 선택
- 선택 전환 빈도
- provider별 선택 비중
- 선택 직후 연결 시도 여부
- provider 상세 로드 실패

## Related Interactions

- [SET-007-show_ai_provider_status](SET-007-show_ai_provider_status.md)
- [SET-007-start_provider_oauth_connection](SET-007-start_provider_oauth_connection.md)
- [SET-007-enter_provider_api_key](SET-007-enter_provider_api_key.md)
- [SET-001-swtich_setting_tabs](../SET-001-control_settings_window/SET-001-swtich_setting_tabs.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `241`
- Writing guide: `../../../../META/feature_specs_writing.md`
- Template: `../../template.md`
