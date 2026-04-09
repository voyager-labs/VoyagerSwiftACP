---
interaction_id: "EVM-001-navigate_pages"
interaction_type: "command"
feature: "Navigate Pages"
category_key: "EVM"
feature_id: "EVM-001"
status: "배포 완료"
summary: "Content Pane에서 Entry 클릭하거나 선택해 현재 Content Tab Page를 새 Page로 전환"
related_region: "file_manager_window.content_pane"
menu: "-"
shortcut: "-"
---

# Navigate Pages

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 페이지 전환 대상이 유효한 상태
- 해당 대상을 표시할 권한 또는 접근성이 확보된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 전환 대상이 삭제되었거나, 접근 권한이 사라진 경우
- 네트워크/외장 볼륨 내 전환 시 연결이 끊긴 경우
- 이미 같은 페이지로 이동하려는 경우

## Acceptance Criteria

- [ ] Content Pane에 네비게이션 가능 대상이 있을 때, 사용자가 해당 대상을 선택하여 인터랙션을
      호출하면 해당 타깃을 표시하는 페이지로 전환되고 히스토리에 새 점이 추가됨

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `17`
