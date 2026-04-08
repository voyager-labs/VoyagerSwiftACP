# Compress Entry(ies)

## Metadata

| Field            | Value                                                               |
| ---------------- | ------------------------------------------------------------------- |
| Interaction ID   | EAC-002-compress_entry_ies                                          |
| Interaction Type | command                                                             |
| Feature          | Organize Entries                                                    |
| Category Key     | EAC                                                                 |
| Feature ID       | EAC-002                                                             |
| Status           | 배포 완료                                                           |
| Summary          | 선택한 Entry를 현재 디렉토리에 하나의 압축 파일로 생성              |
| Related Region   | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu             | File                                                                |
| Shortcut         | -                                                                   |

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태
- <<AI>> 압축 파일을 생성할 현재 디렉토리에 대해 쓰기 권한이 있는 상태

## Edge Cases

- <<AI>> 동일 이름의 압축 파일이 이미 존재해 충돌이 발생하는 경우
- <<AI>> 선택 항목이 많거나 커서 처리 시간이 길어 진행 표시가 필요한 경우
- <<AI>> 일부 항목이 접근 불가해 압축에 포함할 수 없는 경우

## Acceptance Criteria

- [ ] <<AI>> 압축 생성이 가능한 상태일 때, 사용자가 해당 인터랙션을 호출하면, 선택한 Entry를 하나의
      압축 파일로 생성함.
- [ ] <<AI>> 이름 충돌이 발생하는 상태일 때, 시스템이 압축 파일을 생성하면, 충돌을 회피하는 이름
      규칙을 적용하거나 사용자에게 선택지를 제공함.
- [ ] <<AI>> 일부 항목이 포함 불가한 상태일 때, 시스템이 압축을 수행하면, 포함 가능한 항목만
      압축하고 제외된 대상과 사유를 사용자에게 안내함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `50`
