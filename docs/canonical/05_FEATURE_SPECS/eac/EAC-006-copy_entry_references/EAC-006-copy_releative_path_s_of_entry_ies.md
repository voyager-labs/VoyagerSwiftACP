# Copy Releative Path(s) of Entry(ies)

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EAC-006-copy_releative_path_s_of_entry_ies |
| Interaction Type | command |
| Feature | Copy Entry References |
| Category Key | EAC |
| Feature ID | EAC-006 |
| Status | 취소 |
| Summary | 선택한 Entry의 현재 디렉토리를 기준으로 한 상대 경로를 클립보드에 복사 |
| Related Region | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu | Edit |
| Shortcut | ⌥⇧⌘C |

## Preconditions

- 하나 이상의 Entry가 선택된 상태
- 기준 디렉토리 컨텍스트를 확정할 수 있는 상태
## Edge Cases

- 기준 디렉토리 컨텍스트가 없는 화면에서 호출되는 경우
- 기준 디렉토리와 멀어 상대 경로가 복잡해지는 경우
- 일부 Entry가 기준 디렉토리와 다른 루트여서 계산이 불가한 경우

## Acceptance Criteria

- [ ] -

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `64`
