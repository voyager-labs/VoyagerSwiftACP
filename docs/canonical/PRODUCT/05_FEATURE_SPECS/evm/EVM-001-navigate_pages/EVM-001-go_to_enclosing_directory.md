# Go to Enclosing Directory

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EVM-001-go_to_enclosing_directory |
| Interaction Type | command |
| Feature | Navigate Pages |
| Category Key | EVM |
| Feature ID | EVM-001 |
| Status | 배포 완료 |
| Summary | 현재 Page가 표시하는 디렉토리의 상위 디렉토리로 이동 |
| Related Region | file_manager_window.content_pane |
| Menu | - |
| Shortcut | ⌘▲ |

## Preconditions

- 현재 페이지가 디렉토리 페이지인 상태
## Edge Cases

- 상위 디렉토리에 접근이 불가능한 경우

## Acceptance Criteria

- [ ] 현재 페이지가 디렉토리 관련을 보여줄 때, 사용자가 해당 인터랙션을 호출하면, 상위 디렉토리 페이지가 로드되고 히스토리에 새로운 페이지로 추가됨

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `21`
