---
interaction_id: "CTM-002-set_current_content_tab_to_next"
interaction_type: "command"
feature: "Set Current Content Tab"
category_key: "CTM"
feature_id: "CTM-002"
status: "준비 완료"
summary: "Content Tab List 상 현재 Content Tab보다 다음 위치의 Content Tab으로 전환"
related_region: "file_manager_window.sidebar.sidebar_body.content_tabs_area"
menu: "-"
shortcut: "⌘⇧]"
---

# Set Current Content Tab to Next

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

- 현재 Content Tab이 Tab List 상 마지막에 위치해 있는 경우

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
- Source line: `207`
