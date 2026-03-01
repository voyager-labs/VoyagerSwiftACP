# Show Selected Entry Counts

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EVM-002-show_selected_entry_counts |
| Interaction Type | display |
| Feature | Configure Entries View |
| Category Key | EVM |
| Feature ID | EVM-002 |
| Status | 배포 완료 |
| Summary | 현재 Page에서 선택된 Entry의 개수를 표시함 |
| Related Region | file_manager_window.content_pane |
| Menu | - |
| Shortcut | - |

## Preconditions

- 현재 페이지가 Entry를 보여주는 페이지인 상태
- 하나 이상의 Entry가 선택된 상태
## Edge Cases

- -

## Acceptance Criteria

- [ ] 현재 페이지가 디렉토리, 콜렉션 등 Entry를 보여줄 수 있는 페이지일 때, 범위 선택, 다중 선택 등으로 선택한 Entry가 존재한다면, 현재 선택한 개수와 전체 개수를 함께 보여줌
- [ ] 선택한 Entry가 존재할 때, 이후 선택이 해제된다면, 즉시 반영되어 다시 View Entry Counts in Current Page를 표시함

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `32`
