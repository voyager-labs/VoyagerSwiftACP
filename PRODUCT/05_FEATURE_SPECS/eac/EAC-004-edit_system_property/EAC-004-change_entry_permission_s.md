# Change Entry Permission(s)

## Metadata

| Field            | Value                                                               |
| ---------------- | ------------------------------------------------------------------- |
| Interaction ID   | EAC-004-change_entry_permission_s                                   |
| Interaction Type | command                                                             |
| Feature          | Edit System Property                                                |
| Category Key     | EAC                                                                 |
| Feature ID       | EAC-004                                                             |
| Status           | 기획 완료                                                           |
| Summary          | 선택한 Entry의 읽기·쓰기·실행 권한과 소유자/그룹을 수정             |
| Related Region   | file_manager_window.content_pane.page_container.page_mode_directory |
| Menu             | File                                                                |
| Shortcut         | -                                                                   |

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태
- <<AI>> 선택한 Entry의 권한을 변경할 권한을 현재 사용자가 가진 상태

## Edge Cases

- <<AI>> 시스템 인증(암호/Touch ID)이 필요한 경우
- <<AI>> 일부 Entry가 시스템 보호/읽기 전용 볼륨 등으로 변경 불가능한 경우
- <<AI>> 일부만 적용 가능해 부분 성공이 발생하는 경우

## Acceptance Criteria

- [ ] <<AI>> 권한 변경이 가능한 상태일 때, 사용자가 해당 인터랙션을 호출하면, 권한/소유자/그룹을
      수정할 수 있는 UI를 표시함.
- [ ] <<AI>> 변경이 확정된 상태일 때, 시스템이 적용하면, 파일 시스템 권한을 갱신하고 결과를 UI에
      반영함.
- [ ] <<AI>> 변경이 불가능하거나 인증이 실패한 상태일 때, 사용자가 적용하면, 권한 변경을 수행하지
      않고 사유를 사용자에게 안내함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `61`
