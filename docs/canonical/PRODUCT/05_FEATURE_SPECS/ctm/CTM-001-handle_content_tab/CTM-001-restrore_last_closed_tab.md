---
interaction_id: "CTM-001-restrore_last_closed_tab"
interaction_type: "command"
feature: "Handle Content Tab"
category_key: "CTM"
feature_id: "CTM-001"
status: "준비 완료"
summary: "가장 최근에 닫은 Content Tab을 복원"
related_region: "file_manager_window.sidebar"
menu: "File"
shortcut: "⌘⇧T"
---

# Restrore Last Closed Tab

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 현재 창에 복원 가능한 최근 닫힌 Content Tab 기록이 존재하는 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<TEMP>> 복구가 불가능한 경우

## Acceptance Criteria

- [ ] <<AI>> 현재 File Manager Window의 최근 닫힌 탭 기록이 존재할 때, 사용자가 해당 인터랙션을
      호출하면, 마지막으로 닫힌 Content Tab이 현재 창에 다시 추가되고 활성화됨.
- [ ] <<AI>> 복원 가능한 최근 닫힌 탭이 현재 창이 아닌 다른 창 또는 이전 세션에 속한 경우, 사용자가
      해당 인터랙션을 호출하면, 정의된 정책(예: 현재 창 기준 기록만 복원)을 따르며 복원 가능 항목이
      없으면 아무 탭도 열리지 않거나 피드백을 표시함.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `199`
