---
interaction_id: "CTM-002-set_current_content_tab_by_index"
interaction_type: "command"
feature: "Set Current Content Tab"
category_key: "CTM"
feature_id: "CTM-002"
status: "준비 완료"
summary: "Content Tab List 상 위치한 번호와 일치하는 Content Tab으로 전환"
related_region: "file_manager_window.sidebar.sidebar_body.content_tabs_area"
menu: "-"
shortcut: "⌘1, ⌘2, ... , ⌘0"
---

# Set Current Content Tab by Index

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 2개 이상의 Content Tab이 열린 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 지정한 번호 위치에 해당하는 Content Tab이 없는 경우

## Acceptance Criteria

- [ ] <<AI>> 지정한 번호 위치에 해당하는 Content Tab이 존재할 때, 사용자가 해당 인덱스에 대한
      인터랙션을 호출하면, 그 번호에 해당하는 Content Tab이 활성화됨.
- [ ] <<AI>> 지정한 번호 위치에 해당하는 Content Tab이 존재하지 않을 때, 사용자가 해당 인터랙션을
      호출하면, 활성 탭이 변경되지 않고 조용히 무시되거나 정의된 피드백을 표시함.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `208`
