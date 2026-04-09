---
interaction_id: "EVM-003-adjust_splited_content_pane_size"
interaction_type: "input"
feature: "Split Content Pane"
category_key: "EVM"
feature_id: "EVM-003"
status: "기획 완료"
summary: "<<AI>> 분할된 Pane 사이의 디바이더를 드래그해 각 Pane의 크기를 조절합니다."
related_region: "file_manager_window.content_pane"
menu: "-"
shortcut: "-"
---

# Adjust Splited Content Pane Size

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> Content Pane이 분할 상태.
- <<AI>> 디바이더가 상호작용 가능 상태.

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 드래그로 한 Pane가 최소 허용 크기 이하로 줄어들려는 경우(클램핑).
- <<AI>> 최대 허용 크기 이상으로 넓히려는 경우(클램핑).
- <<AI>> 드래그 중 Sidebar/Inspector 토글로 가용 공간이 변해 즉시 재계산이 필요한 경우.

## Acceptance Criteria

- [ ] <<AI>> 사용자가 디바이더를 드래그하면 두 Pane의 크기가 정의된 최소–최대 범위 내에서 실시간으로
      조정됨.
- [ ] <<AI>> 경계를 넘어가려는 경우 디바이더가 가장 가까운 허용값에서 멈춤.
- [ ] <<AI>> 레이아웃 제약(예: Sidebar/Inspector 변화)이 발생하면 즉시 반영되어 겹침/잘림 없이
      갱신됨.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `37`
