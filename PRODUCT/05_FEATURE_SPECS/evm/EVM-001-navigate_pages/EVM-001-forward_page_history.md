# Forward Page History

## Metadata

| Field            | Value                                             |
| ---------------- | ------------------------------------------------- |
| Interaction ID   | EVM-001-forward_page_history                      |
| Interaction Type | command                                           |
| Feature          | Navigate Pages                                    |
| Category Key     | EVM                                               |
| Feature ID       | EVM-001                                           |
| Status           | 배포 완료                                         |
| Summary          | 현재 Content Tab Page History 상 다음 Page로 전환 |
| Related Region   | file_manager_window.content_pane.content_header   |
| Menu             | Go                                                |
| Shortcut         | ⌘]                                                |

## Preconditions

- Content Tab Page History 상 '앞으로' 이동 가능한 페이지가 존재하는 상태

## Edge Cases

- 다음 페이지 대상이 더 이상 접근이 불가능한 경우

## Acceptance Criteria

- [ ] 페이지 히스토리에 앞으로 이동 가능한 페이지가 있을 때, 사용자가 해당 인터랙션을 호출하면,
      페이지 스택의 다음 항목으로 전환되고 히스토리 포인터가 한 단계 앞으로 이동한 상태로 기록됨

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `19`
