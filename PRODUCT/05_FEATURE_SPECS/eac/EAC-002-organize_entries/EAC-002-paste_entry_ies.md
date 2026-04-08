# Paste Entry(ies)

## Metadata

| Field            | Value                                                               |
| ---------------- | ------------------------------------------------------------------- |
| Interaction ID   | EAC-002-paste_entry_ies                                             |
| Interaction Type | command                                                             |
| Feature          | Organize Entries                                                    |
| Category Key     | EAC                                                                 |
| Feature ID       | EAC-002                                                             |
| Status           | 배포 완료                                                           |
| Summary          | 클립보드에 저장된 Entry를 현재 디렉토리에 붙여넣기                  |
| Related Region   | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu             | Edit                                                                |
| Shortcut         | ⌘V                                                                  |

## Preconditions

- <<AI>> 클립보드에 하나 이상의 Entry 참조가 저장된 상태
- <<AI>> 현재 페이지가 디렉토리 컨텍스트를 가지는 상태
- <<AI>> 현재 디렉토리에 대해 쓰기 권한이 있는 상태

## Edge Cases

- <<AI>> 클립보드 참조 대상이 삭제·이동되어 접근 불가한 경우
- <<AI>> 대상 디렉토리에 동일 이름 Entry가 존재해 충돌이 발생하는 경우
- <<AI>> 잘라내기 의도에서 자기 자신/자기 하위로 이동하려는 경우
- <<AI>> 디스크 용량 부족/권한 부족으로 부분 성공이 발생하는 경우

## Acceptance Criteria

- [ ] <<AI>> 클립보드에 Entry 참조가 있는 상태일 때, 사용자가 해당 인터랙션을 호출하면, 복사/이동
      의도에 맞게 현재 디렉토리에 붙여넣기를 수행함.
- [ ] <<AI>> 이름 충돌이 발생하는 상태일 때, 시스템이 붙여넣기를 수행하면, 충돌 해결 정책을
      적용하거나 사용자에게 선택지를 제공함.
- [ ] <<AI>> 클립보드가 비어 있거나 붙여넣기 불가한 상태일 때, 사용자가 해당 인터랙션을 호출하면,
      작업을 수행하지 않고 사유를 사용자에게 안내함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `46`
