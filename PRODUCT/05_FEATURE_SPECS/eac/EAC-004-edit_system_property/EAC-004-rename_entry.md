# Rename Entry

## Metadata

| Field            | Value                                                               |
| ---------------- | ------------------------------------------------------------------- |
| Interaction ID   | EAC-004-rename_entry                                                |
| Interaction Type | command                                                             |
| Feature          | Edit System Property                                                |
| Category Key     | EAC                                                                 |
| Feature ID       | EAC-004                                                             |
| Status           | 배포 완료                                                           |
| Summary          | 선택한 Entry의 이름을 편집해 변경                                   |
| Related Region   | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu             | File                                                                |
| Shortcut         | Enter                                                               |

## Preconditions

- <<AI>> 하나의 Entry가 선택된 상태
- <<AI>> 선택한 Entry의 이름을 변경할 수 있는 상태

## Edge Cases

- <<AI>> 새 이름이 비어 있거나 파일명 규칙에 위배되는 경우
- <<AI>> 동일 이름 Entry가 이미 존재해 충돌이 발생하는 경우
- <<AI>> 권한 부족/파일 잠금/외부 변경으로 이름 변경이 실패하는 경우

## Acceptance Criteria

- [ ] <<AI>> 하나의 Entry가 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 해당 Entry가 이름
      편집 모드로 전환됨.
- [ ] <<AI>> 유효한 새 이름이 확정된 상태일 때, 시스템이 적용하면, 파일 시스템 상의 이름이 변경되고
      목록 표시가 갱신됨.
- [ ] <<AI>> 이름 변경이 실패하는 상태일 때, 사용자가 확정하면, 변경을 적용하지 않고 실패 사유를
      안내한 뒤 기존 이름을 유지하도록 함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `58`
