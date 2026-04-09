---
interaction_id: "SET-007-reset_provider_api_key"
interaction_type: "command"
feature: "Manage AI Connections"
category_key: "SET"
feature_id: "SET-007"
status: "드래프트"
summary: "<<AI>> 저장된 API key를 제거하고 미연결 상태로 되돌려 사용자가 새 key를 다시 입력할 수 있게 한다."
related_region: "settings_window.settings_body.tab_ai.provider_connection_area"
menu: "-"
shortcut: "-"
---

# Reset Provider API Key

## Intent

- 사용자에게 잘못된 기존 키를 안전하게 제거하고 새 키로 교체할 수 있는 진입점을 제공한다.
- 기존 키를 남겨두지 않음으로써 보안/운영 리스크를 줄인다.

## Trigger / Entry Points

- API key provider 설정 영역에서 `키 초기화`, `재입력` 등 명령을 선택할 때 호출된다.
- 상태가 오류인 provider를 문제해결 과정에서 초기화할 때 호출된다.

## Preconditions

- 선택된 provider가 API key 기반으로 연결되어 있거나, 과거 API key 입력 이력이 있어야 한다.
- 연결 상태 영역에서 해당 provider 정보가 노출된 상태여야 한다.

## Expected Outcome

- 기존 저장 키 또는 pending key는 제거되고 `미연결` 상태가 되어야 한다.
- 사용자는 동일 provider에 대해 새 key를 입력할 수 있어야 한다.
- 남은 연결 정보는 안전하게 정리되어 불필요하게 노출되지 않아야 한다.

## State Changes

- 저장된 API key 자격이 삭제되거나 비활성화된다.
- provider 상태가 `연결되지 않음`으로 갱신된다.
- 연결 관련 에러/메시지 플래그가 초기 상태로 리셋된다.
- 입력 필드는 비어 있는 기본 상태로 초기화된다.

## User-visible Feedback

- 초기화 성공/실패 결과를 즉시 표시한다.
- 성공 시 입력 필드가 비우고 새 입력 유도 문구를 제공한다.
- 실패 시 기존 키 유지 여부와 재시도 가능성(예: 시스템 저장 오류)을 명확히 표시한다.
- 보안 목적의 경고(동일 세션 저장 데이터 정리 필요성)를 전달할 수 있다.

## Edge Cases / Failure Handling

- 저장된 키가 없는 상태에서 초기화를 수행하면 실패로 처리하지 않고 이미 미연결 상태임을 안내한다.
- 영속 저장소 삭제가 일시적으로 실패하면 사용자에게 재시도 안내와 상태 보류 메시지를 표시한다.
- 인증중인 상태에서 초기화를 요청하면, 진행 취소 후 초기화 여부를 사용자 확인 후 반영해야 한다.
- 다중 창/다중 탭에서 동시 초기화가 발생하면 마지막 이벤트 기준으로 일관성 있게 상태를 정합성
  처리한다.

## Acceptance Criteria

- [ ] API key provider를 선택한 상태에서 `초기화` 액션을 호출하면, 기존 키가 제거되고 상태가
      `미연결`로 바뀌어야 한다.
- [ ] 키가 존재하지 않는 상태에서 초기화를 호출한 경우, 실패를 내지 않고 이미 초기화된 상태를
      유지해야 한다.
- [ ] 키 초기화 성공 후 사용자에게 새 key 입력이 가능한 상태로 UI가 전환되어야 한다.
- [ ] 저장소 삭제 실패와 같은 예외가 발생한 경우, 사용자에게 실패 이유와 재시도 동선을 안내해야
      한다.
- [ ] 초기화가 완료되지 않았을 때는 오탐으로 인해 이전 키가 재노출되지 않아야 한다.

## Permissions / Dependencies

- provider별 API key 저장소의 삭제/갱신 권한이 필요하다.
- 저장 성공/실패 이벤트를 상태 영역에 반영하는 파이프라인이 필요하다.

## Observability / Analytics

- 초기화 시도 횟수
- 키 삭제 성공/실패
- 초기화 후 재입력 시작률
- 초기화 도중 발생한 저장 오류 유형

## Related Interactions

- [SET-007-enter_provider_api_key](SET-007-enter_provider_api_key.md)
- [SET-007-show_ai_provider_status](SET-007-show_ai_provider_status.md)
- [SET-007-disconnect_ai_provider](SET-007-disconnect_ai_provider.md)
- [SET-007-verify_provider_api_key](SET-007-verify_provider_api_key.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `248`
