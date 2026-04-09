---
interaction_id: "CDA-001-submit_response_feedback"
interaction_type: "command"
feature: "Handle User Request"
category_key: "CDA"
feature_id: "CDA-001"
status: "기획 완료"
summary: "생성된 응답에 대해 Good/Bad 평가와 선택적 코멘트를 저장"
related_region: "file_manager_window.inspector_pane.inspector_mode_chat"
menu: "-"
shortcut: "-"
---

# Submit Response Feedback

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> 대상 Message에 Assistant Response가 표시된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> Good/Bad를 반복 변경하는 경우
- <<AI>> 전송 실패/오프라인인 경우

## Acceptance Criteria

- [ ] <<AI>> 응답이 표시된 상태일 때, 사용자가 Good 또는 Bad를 선택하면, 평가가 해당 응답에 연결되어
      저장됨.
- [ ] <<AI>> Bad 선택 후 코멘트를 입력하면, 코멘트가 함께 저장됨.
- [ ] <<AI>> 반복 변경 시, 마지막 선택이 유효하게 반영됨.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `148`
