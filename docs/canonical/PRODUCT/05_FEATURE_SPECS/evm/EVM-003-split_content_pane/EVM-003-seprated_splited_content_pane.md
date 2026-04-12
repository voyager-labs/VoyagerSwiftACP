---
interaction_id: "EVM-003-seprated_splited_content_pane"
interaction_type: "command"
feature: "Split Content Pane"
category_key: "EVM"
feature_id: "EVM-003"
status: "기획 완료"
summary: "<<AI>> 두 분할 Pane의 세션/네비게이션을 분리하여 서로 다른 페이지/경로를 독립적으로 탐색합니다."
related_region: "file_manager_window.content_pane"
menu: "-"
shortcut: "-"
---

# Seprated Splited Content Pane

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> Content Pane이 분할 상태.
- <<AI>> 각 Pane의 히스토리/세션을 개별로 유지할 수 있는 상태.

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 한 Pane에서 접근 불가 경로/네트워크 끊김 발생 시 해당 Pane만 오류/안내를 표시하고 다른
  Pane은 정상 유지.
- <<AI>> 동일 리소스에 대한 동시 편집/잠금 충돌이 발생할 수 있는 경우.

## Acceptance Criteria

- [ ] <<AI>> 사용자가 인터랙션을 호출하면 두 Pane의 세션/네비게이션이 분리되어 각 Pane에서 서로 다른
      페이지/경로를 독립적으로 탐색 가능함.
- [ ] <<AI>> 각 Pane의 히스토리는 별도로 기록되며, 링크/열기 등 액션은 현재 포커스 Pane에만 적용됨.
- [ ] <<AI>> 한 Pane의 오류는 다른 Pane의 표시/조작에 영향을 주지 않음.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `36`
