# Open Entry with Selected App

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EAC-001-open_entry_with_selected_app |
| Interaction Type | command |
| Feature | Execute Entry |
| Category Key | EAC |
| Feature ID | EAC-001 |
| Status | 배포 완료 |
| Summary | 선택한 Entry를 사용자가 지정한 앱으로 실행 |
| Related Region | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu | File |
| Shortcut | ⌥⌘▼ |

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태
- <<AI>> 앱 선택 UI를 표시할 수 있는 상태
## Edge Cases

- <<AI>> 사용자가 앱 선택 UI를 취소하는 경우
- <<AI>> 선택한 앱이 설치되어 있지 않거나 실행 불가능한 경우
- <<AI>> 선택한 앱이 일부 Entry 유형을 지원하지 않는 경우

## Acceptance Criteria

- [ ] <<AI>> 하나 이상의 Entry가 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 앱 선택 UI를 표시함.
- [ ] <<AI>> 사용자가 앱을 선택한 상태일 때, 시스템이 실행을 시작하면, 선택한 Entry들을 지정한 앱으로 실행함.
- [ ] <<AI>> 사용자가 앱 선택을 취소한 상태일 때, 시스템이 처리를 종료하면, 아무 변화도 발생하지 않도록 함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `40`
