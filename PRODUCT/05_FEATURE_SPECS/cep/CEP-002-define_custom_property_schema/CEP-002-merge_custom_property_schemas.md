---
interaction_id: "CEP-002-merge_custom_property_schemas"
interaction_type: "command"
feature: "Define Custom Property Schema"
category_key: "CEP"
feature_id: "CEP-002"
status: "아이디어"
summary: "<<AI>> 선택한 여러 사용자 프로퍼티 스키마를 하나의 타깃 스키마로 병합하는 설정 플로우를 제공한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_property"
menu: "<<AI>> Edit"
shortcut: "-"
---

# Merge Custom Property Schemas

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> 병합할 스키마 2개 이상이 선택된 상태- 병합 결과로 남길 타깃 스키마가 지정된 상태
- <<AI>> 병합 및 값 마이그레이션을 실행할 권한을 보유한 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 선택한 스키마들의 타입이 서로 달라 병합 규칙을 정할 수 없는 경우
- <<AI>> 동일 엔트리에 여러 스키마 값이 동시에 존재해 충돌 해결이 필요한 경우
- <<AI>> 옵션 값(enum) 또는 제약 조건이 서로 달라 단순 병합이 불가능한 경우
- <<AI>> 병합 실행 중 일부 엔트리 값 마이그레이션이 실패하는 경우

## Acceptance Criteria

- [ ] <<AI>> 2개 이상의 스키마가 선택된 상태일 때, 사용자가 병합 플로우를 시작하면, 타깃 스키마와
      충돌 처리 규칙을 설정하는 화면을 표시함.
- [ ] <<AI>> 병합 설정이 유효한 상태일 때, 사용자가 실행하면, 병합 작업을 생성하고 값 마이그레이션
      작업을 예약하거나 시작함.
- [ ] <<AI>> 병합이 완료된 상태일 때, 사용자가 스키마 목록을 확인하면, 소스 스키마를 제거하거나
      비활성화하고 모든 참조를 타깃 스키마로 통합함.
- [ ] <<AI>> 병합 설정이 불가능한 조합인 상태일 때, 사용자가 실행을 시도하면, 실행을 차단하고 이유와
      대안을 표시함.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `185`
