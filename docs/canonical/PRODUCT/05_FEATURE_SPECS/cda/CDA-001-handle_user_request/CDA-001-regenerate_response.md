---
interaction_id: "CDA-001-regenerate_response"
interaction_type: "command"
feature: "Handle User Request"
category_key: "CDA"
feature_id: "CDA-001"
status: "기획 완료"
summary: "특정 User Request Message에 대해 응답을 재생성하도록 새 생성 Run을 시작하고, 기존 응답은 버전으로 보존"
related_region: "file_manager_window.inspector_pane.inspector_mode_chat"
menu: "-"
shortcut: "-"
---

# Regenerate Response

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> 대상 Message에 Assistant Response가 존재하는 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 기존 스트리밍이 진행 중인 경우
- <<AI>> 연속 재호출하는 경우

## Acceptance Criteria

- [ ] <<AI>> 응답이 존재할 때, 사용자가 호출하면, 기존 응답은 이전 버전으로 유지되고 새 응답 생성이
      시작됨.
- [ ] <<AI>> 생성 중 재호출하면, 중복 실행이 방지되고 마지막 요청만 유효하게 처리됨.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `147`
