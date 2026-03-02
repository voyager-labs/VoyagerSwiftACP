# Delete Collection

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-002-delete_collection |
| Interaction Type | command |
| Feature | Manage Retrieval Collections |
| Category Key | RCL |
| Feature ID | RCL-002 |
| Status | 배포 완료 |
| Summary | 현재 보고 있는 콜렉션 파일을 삭제하고 닫음 |
| Related Region | file_manager_window.content_pane.content_header.page_menu_area |
| Menu | File |
| Shortcut | - |

## Preconditions

- 현재 페이지가 콜렉션 페이지인 상태
## Edge Cases

- 다른 탭/뷰에서 동일 콜렉션 페이지가 열려 있는 경우

## Acceptance Criteria

- [ ] 현재 페이지가 콜렉션 페이지인 상태일 때, 사용자가 해당 인터랙션을 호출하면, 삭제를 확인하는 확인창이 나타남
- [ ] 사용자가 삭제를 시도했을 때, 삭제가 성공했다면, 현재 콜렉션 파일을 휴지통으로 옮기거나 완전히 삭제하고, 현재 페이지를 닫음
- [ ] 사용자가 삭제를 확정했을 때, 다른 뷰에서 동일 콜렉션 페이지가 열려 있는 상태라면, 해당 뷰가 대상 없음 상태로 전환됨

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `128`
