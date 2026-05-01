---
interaction_id: "CDA-001-submit_message"
interaction_type: "command"
feature: "Handle User Request"
category_key: "CDA"
feature_id: "CDA-001"
status: "준비 완료"
summary: "Chat Pane 인풋 필드에 입력된 Message를 제출해 User Request 처리 플로우를 시작"
related_region: "file_manager_window.inspector_pane.inspector_mode_chat"
menu: "-"
shortcut: "Enter"
---

# Submit Message

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 채팅 입력창이 포커스 상태
- 입력된 Message가 공백이 아닌 상태
- 이전에 제출된 Message가 처리 중이지 않은 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

-   -

## Acceptance Criteria

- [ ] Chat Pane의 인풋 필드가 입력된 Message가 공백이 아닌 상태일 때, 사용자가 해당 인터랙션을
      호출하면, 새 User Request가 생성되고 채팅 히스토리에 Message가 추가됨
- [ ] 사용자가 해당 인터랙션을 호출했을 때, 이전에 제출된 Message가 처리 중인 상태라면, 새 Submit
      Message를 제출이 막힘
- [ ] 인풋 필드가 포커스된 상태일 때, 할당된 키보드 숏컷을 누르면, 해당 인터랙션이 호출됨

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `139`
