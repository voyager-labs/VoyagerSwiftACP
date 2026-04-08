# Enter Provider API Key

## Metadata

| Field            | Value                                                                         |
| ---------------- | ----------------------------------------------------------------------------- |
| Interaction ID   | SET-007-enter_provider_api_key                                                |
| Interaction Type | input                                                                         |
| Feature          | Manage AI Connections                                                         |
| Category Key     | SET                                                                           |
| Feature ID       | SET-007                                                                       |
| Status           | 드래프트                                                                      |
| Summary          | <<AI>> 선택한 provider에 사용할 API key를 입력하고 저장 대기 상태로 유지한다. |
| Related Region   | settings_window.settings_body.tab_ai.provider_connection_area                 |
| Menu             | -                                                                             |
| Shortcut         | -                                                                             |

## Intent

- 사용자가 provider별 자격을 앱에 전달하기 위한 입력을 완료할 수 있게 한다.
- 즉시 연결은 하지 않고 입력만 저장(임시 대기)해 사용자가 수정할 여지를 남긴다.

## Trigger / Entry Points

- AI 탭에서 API key 방식으로 설정 가능한 provider를 선택했을 때 호출된다.
- API key 입력 필드에 포커스가 이동하거나, 기존 입력 값을 다시 편집할 때 호출된다.

## Preconditions

- Settings 창이 열려 있고 AI 탭에서 선택된 provider가 존재해야 한다.
- provider가 API key 기반 연결을 지원해야 한다.
- 저장하려는 키 입력 영역이 사용자에게 노출되어야 한다.

## Expected Outcome

- 사용자가 key 입력을 완료하면, UI가 ‘저장 대기’ 상태로 바뀌고 검증 전 상태임을 보여야 한다.
- 입력값이 유효 형식을 벗어날 경우, 확인하기 쉬운 validation 피드백이 표시되어야 한다.
- 기존 연결 정보는 즉시 파기되지 않고 사용자가 재확인할 수 있어야 한다.

## State Changes

- provider별 API key 입력 버퍼가 `pending` 상태로 유지된다.
- 입력 길이, 마지막 편집 시각, 유효성 상태(기본 검사) 등이 UI 상태로 반영된다.
- 기존 저장 키는 별도 동작(검증/재설정) 없이는 즉시 삭제되지 않는다.

## User-visible Feedback

- 입력 필드에 비노출(마스킹) 표시가 적용될 수 있다.
- 유효성 힌트(형식 미충족, 빈 값, 특수문자 경고 등)를 제공한다.
- 입력이 변경될 때마다 `저장 대기` 상태와 검증 버튼 활성화 여부를 표시한다.
- 저장 대기 상태에서 실수 방지를 위한 `초기화` 또는 `취소` 동작을 제공할 수 있다.

## Edge Cases / Failure Handling

- 입력값에 앞뒤 공백만 있는 경우 유효하지 않은 값으로 판별하고 경고해야 한다.
- 긴 키가 붙여넣기된 경우 잘림 없이 저장 가능해야 하며, 과도하게 긴 값은 상한 안내로 제어한다.
- provider가 API key 방식을 더 이상 지원하지 않게 되면 입력 UI를 비활성화한다.
- 앱이 백그라운드로 갈 경우 입력 버퍼가 사라질 수 있으므로 경고 후 복구 경로를 남긴다.
- 다중 provider에서 빠르게 전환할 경우, 이전 provider의 미검증 값을 임의로 대상 전환하지 않도록
  격리해야 한다.

## Acceptance Criteria

- [ ] API key 방식 provider를 선택한 상황에서, 사용자가 키를 입력하면, 입력값이 즉시 `저장 대기`
      상태로 표시되어야 한다.
- [ ] 잘못된 형식(공백/빈 값)으로 입력하면, 저장 대기가 아니라 유효성 경고가 표시되어야 한다.
- [ ] 유효한 형식의 키를 입력하면, 검증/연결 버튼이 활성화되어야 한다.
- [ ] API key 방식이 아닌 provider에서 해당 상호작용을 호출하면, 입력 영역은 비노출되거나
      비활성화되어야 한다.
- [ ] 입력 화면을 변경한 상태에서 앱이 강제로 종료된 뒤 복귀 시, 사용자는 입력 보존 또는 재입력
      안내를 받게 된다.

## Permissions / Dependencies

- provider별 API key 입력 컴포넌트가 노출되어야 한다.
- API key가 안전하게 저장 대기될 수 있는 임시 저장 메커니즘이 필요하다.
- 최종 검증은 `SET-007-verify_provider_api_key`에 의존한다.

## Observability / Analytics

- API key 입력 노출 횟수
- 입력 변경 빈도 및 형식 경고 횟수
- provider 전환으로 인해 폐기된 pending 입력 횟수

## Related Interactions

- [SET-007-verify_provider_api_key](SET-007-verify_provider_api_key.md)
- [SET-007-reset_provider_api_key](SET-007-reset_provider_api_key.md)
- [SET-007-select_ai_provider](SET-007-select_ai_provider.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `246`
- Writing guide: `../../../../META/feature_specs_writing.md`
- Template: `../../template.md`
