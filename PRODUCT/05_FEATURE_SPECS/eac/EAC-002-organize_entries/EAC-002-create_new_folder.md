# Create New Folder

## Metadata

| Field            | Value                                                               |
| ---------------- | ------------------------------------------------------------------- |
| Interaction ID   | EAC-002-create_new_folder                                           |
| Interaction Type | command                                                             |
| Feature          | Organize Entries                                                    |
| Category Key     | EAC                                                                 |
| Feature ID       | EAC-002                                                             |
| Status           | 배포 완료                                                           |
| Summary          | 현재 디렉토리에 새 폴더를 생성하고 곧바로 이름 편집 모드로 진입     |
| Related Region   | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu             | File                                                                |
| Shortcut         | ⌘⇧N                                                                 |

## Preconditions

- <<AI>> 현재 페이지가 디렉토리 컨텍스트를 가지는 상태
- <<AI>> 현재 디렉토리에 대해 쓰기 권한이 있는 상태

## Edge Cases

- <<AI>> 현재 디렉토리가 읽기 전용이거나 권한 부족인 경우
- <<AI>> 동일 이름 폴더가 이미 존재해 이름 충돌이 발생하는 경우
- <<AI>> 스토리지 지연으로 생성 결과 반영이 지연되는 경우

## Acceptance Criteria

- [ ] <<AI>> 생성 가능한 디렉토리 컨텍스트일 때, 사용자가 해당 인터랙션을 호출하면, 현재 디렉토리에
      새 폴더를 생성하고 곧바로 이름 편집 모드로 진입함.
- [ ] <<AI>> 이름 충돌이 발생하는 상태일 때, 시스템이 폴더를 생성하면, 충돌을 회피하는 이름 규칙으로
      생성하거나 사용자에게 이름 변경을 유도함.
- [ ] <<AI>> 권한 문제로 생성할 수 없는 상태일 때, 사용자가 해당 인터랙션을 호출하면, 폴더를
      생성하지 않고 실패 사유를 사용자에게 안내함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `43`
