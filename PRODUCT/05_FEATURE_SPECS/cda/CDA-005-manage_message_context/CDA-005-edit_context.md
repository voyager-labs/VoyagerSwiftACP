---
interaction_id: "CDA-005-edit_context"
interaction_type: "command"
feature: "Manage Message Context"
category_key: "CDA"
feature_id: "CDA-005"
status: "기획 완료"
summary: "추가된 해당 컨텍스트를 다른 컨텍스트 요소로 교체"
related_region: "file_manager_window.inspector_pane.inspector_mode_chat"
menu: "-"
shortcut: "-"
---

# Edit Context

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> 현재 챗 필드에 하나 이상의 컨텍스트 칩이 추가된 상태
- <<AI>> 교체 대상으로 삼을 기존 컨텍스트 칩이 선택되었거나 편집 UI를 통해 지정된 상태
- <<AI>> 컨텍스트 드랍다운 또는 선택 UI에 새로운 컨텍스트 후보가 하나 이상 존재하는 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 새로 선택한 컨텍스트가 기존 컨텍스트와 동일한 대상인 경우
- <<AI>> 새로 선택한 컨텍스트 대상이 선택 시점에 삭제되었거나 접근 권한이 사라진 상태인 경우
- <<AI>> 기존 컨텍스트가 여러 Intent에서 동시에 사용될 수 있는 구성에서, 교체가 다른 Intent 해석에
  영향을 줄 수 있는 경우

## Acceptance Criteria

- [ ] <<AI>> 기존 컨텍스트 칩이 선택된 상태에서 사용자가 Edit Context 인터랙션으로 다른 유효한
      컨텍스트 요소를 선택하면, 해당 컨텍스트 칩이 새 대상으로 교체되고 메시지의 컨텍스트 목록에서도
      참조 대상이 새 요소로 업데이트됨.
- [ ] <<AI>> 새로 선택한 컨텍스트가 기존 컨텍스트와 동일한 대상인 상태에서 Edit Context 인터랙션이
      실행되면, 컨텍스트 대상은 변경되지 않고 메시지 컨텍스트 구성에 추가적인 변화가 발생하지 않음.
- [ ] <<AI>> 새로 선택한 컨텍스트 대상이 삭제되었거나 접근 권한이 없는 상태에서 Edit Context
      인터랙션이 실행되면, 기존 컨텍스트는 유지되고 교체가 실패했다는 정보가 사용자에게 표시되거나
      메타데이터에 기록됨.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `173`
