---
interaction_id: "SET-007-verify_provider_api_key"
interaction_type: "background"
feature: "Manage AI Connections"
category_key: "SET"
feature_id: "SET-007"
status: "드래프트"
summary: "<<AI>> 입력된 API key의 형식과 유효성을 확인하고 결과에 따라 연결 상태를 갱신한다."
related_region: "settings_window.settings_body.tab_ai.provider_status_area"
menu: "-"
shortcut: "-"
---

# Verify Provider API Key

## Intent

- 사용자가 입력한 키가 실제 사용 가능한지 판단할 수 있게 하여 잘못된 설정으로 오동작하는 것을
  방지한다.
- 검증 실패/성공에 따라 명확한 상태를 반환해 다음 행동(재시도/연결)을 안내한다.

## Trigger / Entry Points

- API key 입력 후 사용자가 검증 액션을 수행할 때 호출된다.
- 저장 대기 상태에서 자동 검증 트리거가 있거나 앱이 자동 확인을 요구할 때 호출될 수 있다.

## Preconditions

- API key 입력 대기 상태가 존재해야 한다.
- 네트워크와 provider 검증 endpoint 접근이 가능해야 한다.
- 선택된 provider가 API key 방식을 지원해야 한다.

## Expected Outcome

- 유효한 키는 성공적으로 저장되고 `연결됨` 상태가 된다.
- 유효하지 않은 키는 저장되지 않고, 사용자에게 수정 가이드와 재입력 경로를 제공한다.
- 결과와 상태는 즉시 상태 영역에 반영되어야 한다.

## State Changes

- 검증 성공 시 저장(또는 갱신)될 API key와 연결 메타데이터를 저장한다.
- 검증 실패 시 키는 저장되지 않거나 상태를 `오류`로 처리한다.
- 상태 영역의 배지/문구가 `연결됨`, `재검증 필요`, `실패` 등으로 변경된다.
- 최근 검증 시각이 갱신된다.

## User-visible Feedback

- 검증 진행 중 로딩 인디케이터를 표시한다.
- 검증 성공 시 연결 완료 메시지와 provider 상태 변경을 알려준다.
- 검증 실패 시 실패 사유 분류(형식 오류, 만료, 권한 없음, 네트워크 오류)를 사용자에게 보여준다.
- 실패 후에도 재시도 버튼이 노출되도록 한다.

## Edge Cases / Failure Handling

- 입력 형식 자체가 잘못된 경우 형식 오류로 즉시 안내하고 인증 서버 호출을 생략할 수 있어야 한다.
- 검증 API 응답이 지연되면 장시간 진행 상태를 유지하면서 중복 호출을 제한한다.
- 네트워크 장애로 즉시 확인할 수 없으면 실패로 단정하지 않고 `확인 불가`로 처리해 재확인 경로를
  제공한다.
- 키가 이미 오래된 연결로 저장되어 있는 상태에서 새 키를 검증할 경우, 기존 연결과의 동시 충돌을
  방지해야 한다.
- provider 측 정책 변경으로 특정 키 형식이 폐기된 경우, 기존 성공 연결이 유효하지 않게 될 수 있어
  갱신 안내가 필요하다.

## Acceptance Criteria

- [ ] API key 입력 대기 상태에서 사용자 검증을 요청하면, 형식 검사를 통과해 provider 유효성 검사가
      진행되어야 한다.
- [ ] 형식이 유효한 키가 검증되면, 상태 영역이 `연결됨`으로 갱신되어야 한다.
- [ ] 형식이 유효하지 않은 키는 저장되지 않고, 오류 메시지와 함께 입력 수정이 가능해야 한다.
- [ ] 네트워크 장애로 검증이 실패한 상황에서, 즉시 실패로 종료하지 않고 재시도 경로가 제공되어야
      한다.
- [ ] 검증 완료 후에는 저장/상태 갱신 결과가 상태 영역에 즉시 반영되어야 한다.

## Permissions / Dependencies

- 네트워크 연결이 필요하다.
- provider 검증 endpoint에 접근할 수 있어야 한다.
- 키 저장/교체 정책(저장 위치, 암호화 방식)과 연결되어야 한다.
- 입력 동작은 `SET-007-enter_provider_api_key`에 연동된다.

## Observability / Analytics

- API key 검증 요청 수
- 형식 실패율
- 외부 검증 응답 실패율
- 검증 성공 후 연결 상태 유지율

## Related Interactions

- [SET-007-enter_provider_api_key](SET-007-enter_provider_api_key.md)
- [SET-007-show_ai_provider_status](SET-007-show_ai_provider_status.md)
- [SET-007-disconnect_ai_provider](SET-007-disconnect_ai_provider.md)

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `247`
