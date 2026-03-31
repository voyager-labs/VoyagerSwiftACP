# View Entry Counts in Current Page

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EVM-002-view_entry_counts_in_current_page |
| Interaction Type | display |
| Feature | Configure Entries View |
| Category Key | EVM |
| Feature ID | EVM-002 |
| Status | 배포 완료 |
| Summary | 현재 Page에 존재하는 Entry의 총 개수를 표시 |
| Related Region | file_manager_window.content_pane |
| Menu | - |
| Shortcut | - |

## Preconditions

- 현재 페이지가 Entry를 보여주는 페이지인 상태
## Edge Cases

- 현재 페이지에 표시 가능한 Entry가 없는 경우
- 숨김 항목 표시 토글 상태에 따라 집계 대상이 달라지는 경우

## Acceptance Criteria

- [ ] 현재 페이지가 디렉토리, 콜렉션 등 Entry를 보여줄 수 있는 페이지일 때, Entry가 존재한다면, 개수를 집계하여 보여줌
- [ ] 현재 페이지가 디렉토리, 콜렉션 등 Entry를 보여줄 수 있는 페이지일 때, Entry가 존재하지 않는다면, 0개로 표시됨
- [ ] 사용자가 폴더 변경, 필터 변경, 숨김 토글 등 인터랙션을 실행했을 때, Entry 결과 집합의 개수가 변한다면, 즉시 갱신되어 반영됨

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `31`
