# Show Page History

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EVM-001-show_page_history |
| Interaction Type | command |
| Feature | Navigate Pages |
| Category Key | EVM |
| Feature ID | EVM-001 |
| Status | 배포 완료 |
| Summary | 현재 Content Tab의 페이지 히스토리를 드랍다운 리스트로 표시 |
| Related Region | file_manager_window.content_pane.content_header |
| Menu | - |
| Shortcut | - |

## Preconditions

- 현재 Content Tab Page History가 최소 1개 이상 존재하는 상태
## Edge Cases

- -

## Acceptance Criteria

- [ ] 페이지 히스토리가 한 개 이상 존재할 때, 사용자가 해당 인터랙션을 호출하면, 해당 Content Tab에서 페이지 전환 히스토리가 드랍다운 리스트로 표시됨
- [ ] 페이지 히스토리 드랍다운 리스트가 표시되었을 때, 사용자가 리스트 상 히스토리 항목을 선택하면, 해당 히스토리로 전환되고, 히스토리 포인터가 해당 위치로 이동한 상태로 기록됨

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `20`
