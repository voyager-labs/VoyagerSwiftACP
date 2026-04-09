---
interaction_id: "EIX-003-create_indexing_exclusion_rule"
interaction_type: "command"
feature: "Configure Indexed Entries"
category_key: "EIX"
feature_id: "EIX-003"
status: "준비 완료"
summary: "인덱싱 제외 규칙을 새로 생성해 규칙 목록에 추가"
related_region: "settings_window.settings_body.tab_indexing"
menu: "-"
shortcut: "-"
---

# Create Indexing Exclusion Rule

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<TEMP>>
- 제외 규칙 편집 화면이 표시된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 입력한 경로·패턴이 유효하지 않아 규칙을 저장할 수 없는 경우
- 새 규칙이 기존 규칙과 중복되는 경우

## Acceptance Criteria

- [ ] 제외 규칙 편집 화면이 표시된 상태일 때, 사용자가 규칙 생성을 저장하면, 시스템이 새 제외 규칙을
      생성하고 규칙 목록에 반영함
- [ ] 입력한 경로·패턴이 유효하지 않은 경우일 때, 사용자가 저장하면, 시스템이 저장을 차단하고
      유효하지 않은 입력을 표시함
- [ ] 새 규칙이 기존 규칙과 중복되는 경우일 때, 사용자가 저장하면, 시스템이 저장을 차단하거나 충돌을
      해소하도록 안내함

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `80`
