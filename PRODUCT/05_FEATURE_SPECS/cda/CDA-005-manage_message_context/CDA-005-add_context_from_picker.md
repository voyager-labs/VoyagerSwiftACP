---
interaction_id: "CDA-005-add_context_from_picker"
interaction_type: "command"
feature: "Manage Message Context"
category_key: "CDA"
feature_id: "CDA-005"
status: "기획 완료"
summary: "챗 필드의 컨텍스트 추가 버튼을 통해 컨텍스트 드랍다운을 열고, 사용자가 선택한 엔트리 등 컨텍스트 요소를 현재 메시지의 컨텍스트로 추가"
related_region: "file_manager_window.inspector_pane.inspector_mode_chat"
menu: "-"
shortcut: "-"
---

# Add Context from Picker

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> 챗 필드가 표시된 상태이고 Chat Pane이 활성화된 상태
- <<AI>> 챗 필드 상단 또는 인근에 컨텍스트 추가 버튼이 표시된 상태
- <<AI>> 컨텍스트 드랍다운에 표시할 후보 컨텍스트 요소가 하나 이상 존재하는 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 사용자가 컨텍스트 드랍다운을 열었지만 어떤 항목도 선택하지 않고 취소하거나 포커스를 잃는
  경우
- <<AI>> 이미 현재 메시지의 컨텍스트로 추가된 요소를 다시 선택하는 경우
- <<AI>> 드랍다운에 표시된 후보 중 일부가 선택 시점에 삭제되었거나 접근 권한이 사라진 상태인 경우

## Acceptance Criteria

- [ ] <<AI>> 컨텍스트 후보가 하나 이상 존재하는 상태에서 사용자가 드랍다운에서 유효한 컨텍스트
      요소를 선택하면, 해당 요소가 현재 메시지의 컨텍스트 목록에 추가되고 챗 필드 상단에 컨텍스트
      칩으로 표시됨.
- [ ] <<AI>> 이미 추가된 컨텍스트 요소를 다시 선택한 상태에서 사용자가 해당 인터랙션을 수행하면,
      중복 컨텍스트가 추가되지 않거나, 중복을 허용하는 설정이라면 동일 요소가 한 번만 사용되도록
      정의된 동작(예: 기존 항목 강조)이 수행됨.
- [ ] <<AI>> 드랍다운에 표시된 요소가 선택 시점에 유효하지 않은 상태일 때, 사용자가 해당 요소를
      선택하면, 컨텍스트로 추가되지 않고 오류 또는 사용 불가 상태가 사용자에게 표시

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `169`
