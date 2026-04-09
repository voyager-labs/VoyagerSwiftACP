---
interaction_id: "FMW-001-open_new_file_manager_window"
interaction_type: "command"
feature: "Control File Manager Window"
category_key: "FMW"
feature_id: "FMW-001"
status: "배포 완료"
summary: "현재 사용 중인 데스크탑에서 새 File Manager 창을 생성해 새로운 세션을 시작"
related_region: "file_manager_window"
menu: "File"
shortcut: "⌘N"
---

# Open New File Manager Window

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 앱 활성 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 사용 가능한 메모리가 부족한 상태에서 호출되는 경우

## Acceptance Criteria

- [ ] 앱이 활성 상태일 때, 사용자가 해당 인터랙션을 호출하면, 현재 데스크탑에 새 File Manager
      Window가 하나 생성되고 활성 창으로 전환됨
- [ ] 시스템 메모리 또는 리소스 부족으로 새 창을 생성할 수 없는 상태일 때, 사용자가 해당 인터랙션을
      호출하면, 새 창이 생성되지 않음

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `3`
