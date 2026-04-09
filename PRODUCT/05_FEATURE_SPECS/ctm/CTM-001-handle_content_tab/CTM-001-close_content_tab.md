---
interaction_id: "CTM-001-close_content_tab"
interaction_type: "command"
feature: "Handle Content Tab"
category_key: "CTM"
feature_id: "CTM-001"
status: "준비 완료"
summary: "현재 Content Tab을 닫음"
related_region: "file_manager_window.sidebar.sidebar_body.content_tabs_area"
menu: "File"
shortcut: "⌘W"
---

# Close Content Tab

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 닫을 Content Tab이 활성 상태거나 지정된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 마지막 남은 Content Tab을 닫는 경우
- 닫으려는 Content Tab에 진행 중인 상태의 작업이 있는 경우

## Acceptance Criteria

- [ ] <<AI>> 닫을 Content Tab이 활성 상태이고 저장되지 않은 변경 사항이 없을 때, 사용자가 해당
      인터랙션을 호출하면, 해당 탭이 닫히고 인접한 탭이 활성화됨.
- [ ] <<AI>> 닫을 Content Tab에 저장되지 않은 변경 사항이 있을 때, 사용자가 해당 인터랙션을
      호출하면, 닫기 여부를 묻는 확인 대화를 표시하고 사용자가 닫기를 선택하면 변경 사항 처리 후
      탭을 닫음.
- [ ] <<AI>> 해당 File Manager Window에 마지막 하나의 Content Tab만 남은 상태에서 사용자가 해당
      인터랙션을 호출하면, 정의된 정책(예: 빈 탭 생성 또는 창 닫기)에 따라 동작하고 그 결과를
      일관되게 유지함.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `194`
