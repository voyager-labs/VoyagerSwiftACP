---
interaction_id: "CDA-005-add_selection_as_context"
interaction_type: "command"
feature: "Manage Message Context"
category_key: "CDA"
feature_id: "CDA-005"
status: "기획 완료"
summary: "콘텐트 패인에서 선택된 엔트리 집합을 현재 메시지의 컨텍스트로 추가"
related_region: "file_manager_window.inspector_pane.inspector_mode_chat"
menu: "Context"
shortcut: "-"
---

# Add Selection as Context

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> Content Pane에서 하나 이상의 엔트리가 선택된 상태
- <<AI>> Chat Pane과 챗 필드가 표시된 상태
- <<AI>> 선택된 엔트리에 대해 현재 사용자에게 최소 읽기 권한이 있는 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 선택된 엔트리가 너무 많아 하나의 컨텍스트로 처리하기에 부담이 되는 경우
- <<AI>> 선택된 엔트리 중 일부는 접근 권한이 없거나 삭제·이동 등으로 실제로 참조할 수 없는 경우
- <<AI>> 선택 상태가 빠르게 변경되는 타이밍(선택 해제·재선택 등)에 인터랙션이 호출되는 경우

## Acceptance Criteria

- [ ] <<AI>> 하나 이상의 엔트리가 선택된 상태에서 사용자가 해당 인터랙션을 호출하면, 선택된 엔트리
      집합이 현재 메시지의 컨텍스트로 추가되고 하나의 컨텍스트 칩으로 표시됨.
- [ ] <<AI>> 선택된 엔트리 중 일부에 접근할 수 없는 상태일 때, 사용자가 해당 인터랙션을 호출하면,
      접근 가능한 엔트리만 컨텍스트로 포함되고 제외된 엔트리에 대해서는 제외 사유가 메타데이터로
      기록되거나 사용자에게 안내됨.
- [ ] <<AI>> 선택된 엔트리가 없는 상태에서 사용자가 해당 인터랙션을 호출하면, 컨텍스트가 추가되지
      않고 아무 변화도 일어나지 않음.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `170`
