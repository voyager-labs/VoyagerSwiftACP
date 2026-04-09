---
interaction_id: "CTM-004-switch_content_tab_via_used_content_tabs_switcher"
interaction_type: "command"
feature: "Switch Content Tab with Used Content Tabs Switcher"
category_key: "CTM"
feature_id: "CTM-004"
status: "준비 완료"
summary: "Used Content Tabs Switcher 상 선택한 Content Tab으로 전환"
related_region: "file_manager_window.sidebar.sidebar_body.content_tabs_area"
menu: "-"
shortcut: "-"
---

# Switch Content Tab via Used Content Tabs Switcher

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- Used Content Tabs Switcher가 화면에 표시된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<TEMP>> 현재 탭이 선택된 경우

## Acceptance Criteria

- [ ] <<AI>> Used Content Tabs Switcher가 표시된 상태에서 사용자가 해당 인터랙션을 호출하면,
      Switcher 내 현재 선택된 Content Tab이 활성화되고 Switcher는 닫힘.
- [ ] <<AI>> Switcher 표시 시간이 만료되거나 포커스를 잃어 자동으로 닫힌 직후 사용자가 해당
      인터랙션을 호출하면, 탭 전환이 발생하지 않고 조용히 무시되거나 Switcher가 재호출됨.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `210`
