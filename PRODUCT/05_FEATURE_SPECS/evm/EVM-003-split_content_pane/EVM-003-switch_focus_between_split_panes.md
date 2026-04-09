---
interaction_id: "EVM-003-switch_focus_between_split_panes"
interaction_type: "command"
feature: "Split Content Pane"
category_key: "EVM"
feature_id: "EVM-003"
status: "기획 완료"
summary: "<<AI>> 키보드 포커스를 좌/우(또는 상/하) Pane 사이에서 전환합니다."
related_region: "file_manager_window.content_pane"
menu: "-"
shortcut: "-"
---

# Switch Focus between Split Panes

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> Content Pane이 분할 상태.
- <<AI>> 포커스 전환 가능한 입력/상태(편집/모달 종료됨).

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 대상 Pane이 모달/입력 잠금 상태로 포커스 전환이 지연/불가한 경우.
- <<AI>> 포커스 전환 직후 키보드 액션이 이전 Pane에 잔류 라우팅되는 레이스 조건.

## Acceptance Criteria

- [ ] <<AI>> 사용자가 인터랙션을 호출하면 키보드 포커스가 좌/우(또는 상/하) Pane으로 즉시 전환됨.
- [ ] <<AI>> 포커스 인디케이터가 전환된 Pane에 표시되고, 키보드 네비게이션/명령이 해당 Pane에만
      라우팅됨.
- [ ] <<AI>> 전환 불가 상태라면 안내를 표시하고 현재 포커스를 유지함.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `38`
