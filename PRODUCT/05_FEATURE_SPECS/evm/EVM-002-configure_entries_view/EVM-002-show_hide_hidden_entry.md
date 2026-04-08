# Show/Hide Hidden Entry

## Metadata

| Field            | Value                                                                                  |
| ---------------- | -------------------------------------------------------------------------------------- |
| Interaction ID   | EVM-002-show_hide_hidden_entry                                                         |
| Interaction Type | command                                                                                |
| Feature          | Configure Entries View                                                                 |
| Category Key     | EVM                                                                                    |
| Feature ID       | EVM-002                                                                                |
| Status           | 배포 완료                                                                              |
| Summary          | Entries View에서 숨김 설정된 Entry의 Entry 목록 상에 보이게 하거나, 보이지 않도록 토글 |
| Related Region   | file_manager_window.content_pane                                                       |
| Menu             | View                                                                                   |
| Shortcut         | ⌘⇧.                                                                                    |

## Preconditions

-   -

## Edge Cases

-   -

## Acceptance Criteria

- [ ] 현재 Entry를 보여주는 페이지에 숨김 파일이 존재할 때, 해당 인터랙션을 호출하면, 숨김 설정된
      엔트리가 뷰 상에 표시/해제됨
- [ ] 해당 인터랙션이 호출될 때, View Entry Counts in Current Page가 정상적으로 동작하면, 개수를
      즉시 갱신함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `29`
