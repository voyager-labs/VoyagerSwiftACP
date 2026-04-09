---
interaction_id: "EVM-002-view_entry_counts_in_current_page"
interaction_type: "display"
feature: "Configure Entries View"
category_key: "EVM"
feature_id: "EVM-002"
status: "배포 완료"
summary: "현재 Page에 존재하는 Entry의 총 개수를 표시"
related_region: "file_manager_window.content_pane"
menu: "-"
shortcut: "-"
---

# View Entry Counts in Current Page

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 현재 페이지가 Entry를 보여주는 페이지인 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 현재 페이지에 표시 가능한 Entry가 없는 경우
- 숨김 항목 표시 토글 상태에 따라 집계 대상이 달라지는 경우

## Acceptance Criteria

- [ ] 현재 페이지가 디렉토리, 콜렉션 등 Entry를 보여줄 수 있는 페이지일 때, Entry가 존재한다면,
      개수를 집계하여 보여줌
- [ ] 현재 페이지가 디렉토리, 콜렉션 등 Entry를 보여줄 수 있는 페이지일 때, Entry가 존재하지
      않는다면, 0개로 표시됨
- [ ] 사용자가 폴더 변경, 필터 변경, 숨김 토글 등 인터랙션을 실행했을 때, Entry 결과 집합의 개수가
      변한다면, 즉시 갱신되어 반영됨

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `31`
