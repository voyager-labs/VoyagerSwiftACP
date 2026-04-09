---
interaction_id: "EIX-005-re_extract_content_based_properties_for_selection"
interaction_type: "command"
feature: "Index Content-based Properties"
category_key: "EIX"
feature_id: "EIX-005"
status: "드래프트"
summary: "선택한 Entry 집합에 대해 포맷에 맞는 콘텐츠 프로퍼티 추출 파이프라인을 수동 실행해 자동 프로퍼티 값을 재계산·복구하고 Entry 프로퍼티로 저장"
related_region: "-"
menu: "-"
shortcut: "-"
---

# Re-extract Content-based Properties for Selection

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태
- <<AI>> 선택한 Entry가 콘텐츠 기반 프로퍼티 추출 대상 포맷인 상태
- <<AI>> 콘텐츠 기반 프로퍼티 추출 기능이 활성화된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 선택한 Entry 중 일부가 지원하지 않는 포맷이거나 콘텐츠 읽기가 불가능한 경우
- <<AI>> 선택한 Entry가 매우 많아 작업이 배치로 분할되어야 하는 경우
- <<AI>> 선택한 Entry가 현재 자동 추출 작업이 진행 중이라 중복 실행이 되는 경우

## Acceptance Criteria

- [ ] <<AI>> Entry가 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 선택한 Entry에 대해 콘텐츠
      기반 프로퍼티 재추출 작업을 큐에 등록함.
- [ ] <<AI>> 재추출이 완료된 상태일 때, 시스템이 결과를 반영하면, 자동 프로퍼티 값을 재계산해 Entry
      프로퍼티로 저장함.
- [ ] <<AI>> 재추출이 실패한 상태일 때, 시스템이 오류를 기록하면, 실패 항목을 실패 목록에 추가하고
      오류 상세를 조회 가능하게 함.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `87`
