---
interaction_id: "CDA-002-show_ask_results"
interaction_type: "display"
feature: "Handle Ask Intent"
category_key: "CDA"
feature_id: "CDA-002"
status: "기획 완료"
summary: "생성 완료된 Ask Intent Response를 Chat Pane에 표시"
related_region: "file_manager_window.inspector_pane.inspector_mode_chat"
menu: "-"
shortcut: "-"
---

# Show Ask Results

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 현재 대화에서 Ask Intent에 대한 응답이 하나 이상 생성된 상태
- Inspector Pane이 Chat 모드로 표시된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> Ask 응답 텍스트가 매우 길어 접힘 또는 요약 표시가 필요한 경우
- <<AI>> 동일 User Request에 대해 재질문 또는 재생성이 여러 번 수행된 경우
- <<AI>> 응답 생성 중 취소나 오류가 발생해 부분 응답만 존재하는 경우

## Acceptance Criteria

- [ ] <<AI>> 현재 대화에서 Ask Intent에 대한 응답이 존재하는 상태일 때, 시스템이 Show Ask Results
      인터랙션을 실행하면, 해당 응답이 User Request 단위로 결과 영역에 표시됨.
- [ ] <<AI>> Ask 응답 텍스트가 매우 긴 상태일 때, 시스템이 Show Ask Results 인터랙션을 실행하면,
      요약 또는 접힘 UI를 사용해 주요 내용이 먼저 보이도록 표시됨.
- [ ] <<AI>> Ask 응답이 부분적으로만 생성된 상태일 때, 시스템이 Show Ask Results 인터랙션을
      실행하면, 생성된 부분과 함께 응답이 불완전하다는 상태가 명확히 표시됨.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `151`
