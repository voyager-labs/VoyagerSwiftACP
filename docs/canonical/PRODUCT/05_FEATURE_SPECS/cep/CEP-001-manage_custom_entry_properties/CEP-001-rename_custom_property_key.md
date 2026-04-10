---
interaction_id: "CEP-001-rename_custom_property_key"
interaction_type: "input"
feature: "Manage Custom Entry Properties"
category_key: "CEP"
feature_id: "CEP-001"
status: "드래프트"
summary: "<<AI>> 선택한 엔트리에서 사용 중인 커스텀 프로퍼티의 키 이름을 변경하고, 워크스페이스 전역에서 해당 키를 사용하는 모든 엔트리·규칙·컬렉션 정의를 함께 업데이트한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_property"
menu: "-"
shortcut: "-"
---

# Rename Custom Property Key

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> 이름을 변경할 커스텀 프로퍼티가 선택된 상태
- <<AI>> 대상 프로퍼티가 워크스페이스 스키마로 등록되어 있는 상태
- <<AI>> 프로퍼티 스키마를 편집할 권한을 보유한 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 입력한 새 키가 비어있거나 허용되지 않은 문자·형식을 포함하는 경우
- <<AI>> 입력한 새 키가 기존 다른 스키마 키와 중복되는 경우
- <<AI>> 입력한 새 키가 기존 키와 동일한 경우
- <<AI>> 대상 키가 컬렉션 정의·규칙·필터 조건·Computed Property 수식에서 참조되는 경우
- <<AI>> 참조 업데이트 중 일부 항목 업데이트가 실패하는 경우
- <<AI>> 인젝션이 의심되는 입력이 포함된 경우

## Acceptance Criteria

- [ ] <<AI>> 대상 커스텀 프로퍼티가 선택된 상태일 때, 사용자가 유효한 새 키로 저장하면, 워크스페이스
      전역 스키마 키를 변경하고 해당 키를 참조하는 엔트리·규칙·컬렉션 정의를 새 키로 갱신함.
- [ ] <<AI>> 새 키가 유효하지 않거나 중복인 상태일 때, 사용자가 저장하면, 저장을 차단하고
      중복·유효성 오류를 표시함.
- [ ] <<AI>> 키 변경 작업이 실패한 상태일 때, 시스템이 결과를 표시하면, 기존 키와 참조를 유지하고
      실패 사유 및 재시도 옵션을 표시함.
- [ ] <<AI>> 키 변경이 완료된 상태일 때, 사용자가 관련 화면을 새로 열거나 검색·필터를 수행하면, 기존
      키는 노출하지 않고 새 키만 일관되게 사용함.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `175`
