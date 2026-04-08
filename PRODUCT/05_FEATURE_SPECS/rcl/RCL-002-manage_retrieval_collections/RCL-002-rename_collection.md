# Rename Collection

## Metadata

| Field            | Value                                                          |
| ---------------- | -------------------------------------------------------------- |
| Interaction ID   | RCL-002-rename_collection                                      |
| Interaction Type | input                                                          |
| Feature          | Manage Retrieval Collections                                   |
| Category Key     | RCL                                                            |
| Feature ID       | RCL-002                                                        |
| Status           | 배포 완료                                                      |
| Summary          | 현재 보고 있는 콜렉션의 파일 이름을 변경                       |
| Related Region   | file_manager_window.content_pane.content_header.page_menu_area |
| Menu             | -                                                              |
| Shortcut         | -                                                              |

## Preconditions

- 현재 페이지가 콜렉션 페이지인 상태

## Edge Cases

- 입력된 이름이 비어 있는 경우
- OS 파일시스템 상 허용되지 않는 문자를 포함하는 경우
- 현재 콜렉션이 저장된 경로에 변경하려는 이름과 동일 이름 콜렉션이 이미 존재하는 경우

## Acceptance Criteria

- [ ] 현재 페이지가 콜렉션 페이지인 상태일 때, 사용자가 해당 인터랙션을 호출하면, 현재 콜렉션 파일
      이름을 수정할 수 있는 편집창이 나타남
- [ ] 사용자가 이름 변경을 시도했을 때, 변경이 성공했다면, 현재 콜렉션의 이름을 보여주는 곳이 새
      이름으로 모두 반영됨
- [ ] 사용자가 이름 변경을 시도했을 때, 입력된 이름이 비어 있거나 파일 시스템 상 유효하지 않은
      상태라면, 이름 변경을 수행하지 않고 오류 피드백을 표시함
- [ ] 사용자가 이름 변경을 시도했을 때, 현재 콜렉션이 저장된 경로에 동일 이름의 콜렉션 파일이 이미
      존재한다면, 이름 변경을 수행하지 않고 충돌 피드백을 표시함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `127`
