---
interaction_id: "CEP-002-delete_custom_property_schema"
interaction_type: "command"
feature: "Define Custom Property Schema"
category_key: "CEP"
feature_id: "CEP-002"
status: "아이디어"
summary: "<<AI>> 선택한 사용자 프로퍼티 스키마를 완전히 삭제해 이후 어떤 엔트리에서도 사용할 수 없도록 한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_property"
menu: "<<AI>> Edit"
shortcut: "-"
---

# Delete Custom Property Schema

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> 삭제할 프로퍼티 스키마가 선택된 상태
- <<AI>> 프로퍼티 스키마를 삭제할 권한을 보유한 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 대상 스키마가 하나 이상의 엔트리에서 사용 중인 경우
- <<AI>> 대상 스키마가 컬렉션 정의·규칙·Computed Property에서 참조되는 경우
- <<AI>> 삭제 과정에서 엔트리 값 제거 또는 참조 정리가 부분 실패하는 경우

## Acceptance Criteria

- [ ] <<AI>> 삭제할 스키마가 선택된 상태일 때, 사용자가 삭제를 실행하고 확인하면, 스키마를
      워크스페이스에서 제거하고 이후 신규 편집 UI에서 선택되지 않게 함.
- [ ] <<AI>> 대상 스키마가 사용 중인 상태일 때, 사용자가 삭제를 실행하면, 삭제를 차단하거나 영향
      범위(사용 엔트리 수, 참조 위치)를 요약해 표시함.
- [ ] <<AI>> 스키마 삭제가 완료된 상태일 때, 시스템이 캐시·검색 인덱스를 갱신하면, 컬렉션 필터·규칙
      편집 UI에서 해당 프로퍼티를 더 이상 선택할 수 없게 함.
- [ ] <<AI>> 삭제 작업이 부분 실패한 상태일 때, 시스템이 결과를 표시하면, 성공·실패 대상을 구분해
      표시하고 실패 사유 및 복구/재시도 옵션을 제공함.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `182`
