# Extract Compressed File(s)

## Metadata

| Field            | Value                                                               |
| ---------------- | ------------------------------------------------------------------- |
| Interaction ID   | EAC-002-extract_compressed_file_s                                   |
| Interaction Type | command                                                             |
| Feature          | Organize Entries                                                    |
| Category Key     | EAC                                                                 |
| Feature ID       | EAC-002                                                             |
| Status           | 배포 완료                                                           |
| Summary          | 선택한 압축 파일을 현재 디렉토리 또는 지정한 위치로 해제            |
| Related Region   | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu             | File                                                                |
| Shortcut         | -                                                                   |

## Preconditions

- <<AI>> 하나 이상의 압축 파일 Entry가 선택된 상태
- <<AI>> 압축 해제 대상 위치에 대해 쓰기 권한이 있는 상태

## Edge Cases

- <<AI>> 압축 파일이 손상되었거나 포맷을 지원하지 않는 경우
- <<AI>> 암호가 필요한 압축 파일인 경우
- <<AI>> 해제 결과가 기존 파일과 충돌하는 경우
- <<AI>> 디스크 용량 부족으로 부분 해제가 발생하는 경우

## Acceptance Criteria

- [ ] <<AI>> 압축 파일이 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 현재 디렉토리 또는
      지정한 위치로 압축을 해제함.
- [ ] <<AI>> 암호가 필요한 상태일 때, 시스템이 해제를 수행하면, 암호 입력을 요청하고 올바른 암호가
      제공되면 해제를 진행함.
- [ ] <<AI>> 해제가 불가능하거나 부분 성공하는 상태일 때, 시스템이 해제를 수행하면, 성공/실패 결과와
      사유를 사용자에게 안내함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `51`
