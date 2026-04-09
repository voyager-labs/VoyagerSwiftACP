---
interaction_id: "FMW-001-exit_full_screen_for_file_manager_window"
interaction_type: "command"
feature: "Control File Manager Window"
category_key: "FMW"
feature_id: "FMW-001"
status: "배포 완료"
summary: "전체 화면 모드의 해당 File Manager 창을 원래 창 크기로 되돌림"
related_region: "file_manager_window"
menu: "View"
shortcut: "⌘⌃F; ESC"
---

# Exit Full Screen for File Manager Window

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 대상 창이 전체 화면 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 이전 창 위치/크기를 복원하기 위한 저장된 정보가 디스플레이 구성 변경 등으로 인해 유효하지 않은
  경우

## Acceptance Criteria

- [ ] 대상 File Manager Window가 전체 화면 상태일 때, 사용자가 해당 인터랙션을 호출하면, 전체 화면
      모드가 해제되고 가능한 범위에서 직전 창 위치와 크기로 복원됨
- [ ] 이전 창 위치·크기 정보가 현재 디스플레이 구성과 맞지 않는 경우, 사용자가 해당 인터랙션을
      호출하면, 전체 화면이 해제되고 현재 디스플레이에 적절한 합리적인 위치와 크기로 창이 복원됨

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `6`
