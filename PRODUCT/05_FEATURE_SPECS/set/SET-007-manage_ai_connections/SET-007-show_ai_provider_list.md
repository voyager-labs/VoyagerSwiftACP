---
interaction_id: "SET-007-show_ai_provider_list"
interaction_type: "display"
feature: "Manage AI Connections"
category_key: "SET"
feature_id: "SET-007"
status: "드래프트"
summary: "<<AI>> 현재 빌드에서 지원되는 provider 목록을 표시하고, 각 provider row에 연결 상태, 지원 연결 방식, 기본 액션(Connect/Disconnect)을 함께 보여준다."
related_region: "settings_window.settings_body.tab_ai.provider_list_area"
menu: "-"
shortcut: "-"
---

# Show AI Provider List

## Intent

- 사용자가 현재 빌드에서 어떤 AI provider를 연결할 수 있는지 한눈에 파악할 수 있게 한다.
- provider를 OAuth/API key 같은 방식이 아니라 하나의 연결 객체로 인식하고 row 단위로 연결·해제 흐름으로 진입할 수 있게 한다.

## Trigger / Entry Points

- Settings 창의 AI 탭이 열릴 때 provider 목록 영역을 렌더링하며 호출된다.
- 앱 재실행 이후 연결 상태를 복원한 직후 목록을 다시 표시할 때 호출된다.
- 지원 provider catalog가 갱신되거나 feature flag가 바뀐 뒤 목록을 다시 그릴 때 호출될 수 있다.

## Preconditions

- Settings 창이 열려 있고 AI 탭이 표시된 상태여야 한다.
- 현재 빌드에서 노출 가능한 provider catalog가 준비되어야 한다.
- 현재 빌드 기준 provider catalog에는 `ChatGPT Codex (OAuth only)`와 `OpenAI (API key only)`가 포함되어야 한다.

## Expected Outcome

- provider 목록에는 현재 빌드에서 지원되는 provider만 표시되어야 한다.
- 각 provider row에는 이름, 지원 연결 방식, 현재 연결 상태, 기본 액션이 함께 보여야 한다.
- 연결된 provider는 목록에서 사라지지 않고 같은 row 안에서 상태와 후속 액션이 갱신되어야 한다.
- 명시적인 `active provider` 또는 `default provider` 설정은 노출하지 않으며, 마지막으로 사용한 provider 정보도 UI에 직접 표시하지 않아야 한다.

## State Changes

- provider catalog와 저장된 connection snapshot이 목록 view model로 결합된다.
- 각 row의 primary action은 provider 상태와 지원 방식에 따라 `Connect`, `Disconnect`, `Reconnect` 등으로 계산된다.
- row별 상태와 액션은 개별 provider connection object 기준으로 독립 계산된다.
- 마지막으로 실제 요청에 사용된 provider 정보는 내부 상태로만 유지하고, row 시각 표시에는 직접 노출하지 않는다.

## User-visible Feedback

- 각 row는 provider 이름과 연결 방식을 명확히 구분해 보여준다.
- 현재 상태는 배지 또는 아이콘, 버튼 라벨로 표현된다.
- 연결된 provider는 `Connected` 상태와 함께 관리 가능한 액션이 보여야 한다.
- 미연결 provider는 `Connect` 진입점이 바로 노출되어야 한다.
- 현재 row는 연결 상태와 액션만 보여주고, 마지막으로 사용한 provider 정보는 별도 라벨/아이콘 없이 숨긴다.
- 실패 상태는 긴 설명 문구 대신 row 안의 경고 아이콘/배지로 우선 표시하고, 필요 시 재시도 액션만 함께 노출한다.

## Edge Cases / Failure Handling

- provider catalog를 불러오지 못하면 빈 목록 대신 실패 안내와 재시도 동선을 보여준다.
- 현재 빌드에서 더 이상 지원되지 않는 provider는 기본 목록에 노출하지 않거나 `Unavailable in this build`로 명시한다.
- 저장된 연결 정보는 있으나 현재 빌드에서 해당 provider를 지원하지 않으면 연결 성공으로 오해되지 않도록 별도 안내가 필요하다.
- 일부 provider 상태만 복원 실패하더라도 목록 전체 렌더링은 유지하고 실패 row만 부분 오류로 표시한다.
- 실패 사유는 row에 긴 텍스트로 바로 노출하지 않고, 상태 아이콘/배지와 재시도 액션만으로 우선 표현할 수 있어야 한다.
- 마지막으로 사용한 provider가 더 이상 연결 가능하지 않거나 지원되지 않으면, 해당 기억값은 조용히 무시하거나 정리하고 다른 row를 강제로 선택하거나 강조하지 않는다.

## Acceptance Criteria

- [ ] AI 탭이 열리면 현재 빌드에서 지원되는 provider 목록에 `ChatGPT Codex`와 `OpenAI`가 표시되어야 한다.
- [ ] 각 provider row에는 provider 이름, 지원 연결 방식, 현재 연결 상태, 기본 액션이 함께 표시되어야 한다.
- [ ] 연결된 provider가 있는 상태에서 목록을 다시 표시하면, 해당 provider row는 목록에서 제거되지 않고 상태 배지와 액션만 갱신되어야 한다.
- [ ] provider catalog 로딩에 실패한 상태에서 목록을 표시하면, 빈 화면 대신 실패 안내와 재시도 액션이 제공되어야 한다.
- [ ] 마지막으로 사용한 provider가 기록되어 있는 상태에서 목록을 표시하더라도, 별도 default 설정 UI나 `Last used` 보조 표시는 노출되지 않아야 한다.
- [ ] provider 연결 또는 복원이 실패한 상태에서 목록을 표시하면, row에는 긴 실패 사유 문구 대신 실패 아이콘/배지와 재시도 액션이 우선 노출되어야 한다.

## Permissions / Dependencies

- 현재 빌드에서 지원되는 provider catalog 메타데이터가 필요하다.
- row별 상태 계산은 `SET-007-restore_ai_provider_connection_status`의 결과에 의존한다.

## Observability / Analytics

- provider 목록 노출
- row별 기본 액션 노출 비율
- provider catalog 로드 실패
- provider별 연결 방식 분포

## Related Interactions

- [SET-007-connect_ai_provider](SET-007-connect_ai_provider.md)
- [SET-007-disconnect_ai_provider](SET-007-disconnect_ai_provider.md)
- [SET-007-restore_ai_provider_connection_status](SET-007-restore_ai_provider_connection_status.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `255`
