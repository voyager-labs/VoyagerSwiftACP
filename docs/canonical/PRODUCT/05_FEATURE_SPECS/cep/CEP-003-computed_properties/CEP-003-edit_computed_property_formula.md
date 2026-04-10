---
interaction_id: "CEP-003-edit_computed_property_formula"
interaction_type: "input"
feature: "Computed Properties"
category_key: "CEP"
feature_id: "CEP-003"
status: "아이디어"
summary: "<<AI>> 기존 Computed Property의 수식을 수정해 계산 방식과 참조 프로퍼티 구성을 변경한다."
related_region: "file_manager_window.inspector_pane.inspector_mode_property"
menu: "-"
shortcut: "-"
---

# Edit Computed Property Formula

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> 편집할 Computed Property가 선택된 상태
- <<AI>> Computed Property 수식을 편집할 권한을 보유한 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 수식 변경으로 결과 타입이 변경되어 기존 표시/정렬/필터와 충돌하는 경우
- <<AI>> 참조 프로퍼티가 삭제·비활성화되어 수식을 평가할 수 없는 경우
- <<AI>> 순환 참조가 발생하는 경우
- <<AI>> 재계산 중 일부 엔트리에서만 오류가 발생하는 경우

## Acceptance Criteria

- [ ] <<AI>> 수식 편집 UI가 열린 상태일 때, 사용자가 유효한 새 수식을 저장하면, 계산 방식을
      업데이트하고 대상 엔트리에서 결과를 재계산해 표시함.
- [ ] <<AI>> 수식이 유효하지 않은 상태일 때, 사용자가 저장하면, 저장을 차단하고 오류를 표시함.
- [ ] <<AI>> 재계산 중 오류가 발생한 상태일 때, 시스템이 결과를 기록하면, 오류를 저장하고 오류 조회
      화면에서 확인 가능하게 함.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `190`
