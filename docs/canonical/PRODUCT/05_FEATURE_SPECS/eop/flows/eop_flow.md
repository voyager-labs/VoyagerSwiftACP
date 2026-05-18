# EOP Entry Operations Flow

## Intent

Entry 실행, 정리, 생명주기, 시스템 프로퍼티 편집, 참조 복사 action을 하나의 Entry Operations 흐름으로 정리한다.

## Contract References

- [eop_contract.toml](../contracts/eop_contract.toml)

## Interaction Coverage

- [EOP-001-open_entry_with_default_app](../EOP-001-execute_entry/EOP-001-open_entry_with_default_app.md)
- [EOP-001-open_entry_with_selected_app](../EOP-001-execute_entry/EOP-001-open_entry_with_selected_app.md)
- [EOP-001-set_default_app_for_entry](../EOP-001-execute_entry/EOP-001-set_default_app_for_entry.md)
- [EOP-001-quick_look_entry](../EOP-001-execute_entry/EOP-001-quick_look_entry.md)
- [EOP-002-create_new_folder](../EOP-002-arrange_entries/EOP-002-create_new_folder.md)
- [EOP-002-copy_entry_ies](../EOP-002-arrange_entries/EOP-002-copy_entry_ies.md)
- [EOP-002-cut_entry_ies](../EOP-002-arrange_entries/EOP-002-cut_entry_ies.md)
- [EOP-002-paste_entry_ies](../EOP-002-arrange_entries/EOP-002-paste_entry_ies.md)
- [EOP-002-duplicate_entry_ies](../EOP-002-arrange_entries/EOP-002-duplicate_entry_ies.md)
- [EOP-002-move_entry_ies](../EOP-002-arrange_entries/EOP-002-move_entry_ies.md)
- [EOP-002-create_entry_alias](../EOP-002-arrange_entries/EOP-002-create_entry_alias.md)
- [EOP-002-compress_entry_ies](../EOP-002-arrange_entries/EOP-002-compress_entry_ies.md)
- [EOP-002-extract_compressed_file_s](../EOP-002-arrange_entries/EOP-002-extract_compressed_file_s.md)
- [EOP-003-move_entry_ies_to_trash](../EOP-003-manage_entry_lifecycle/EOP-003-move_entry_ies_to_trash.md)
- [EOP-003-delete_entry_ies_immediately](../EOP-003-manage_entry_lifecycle/EOP-003-delete_entry_ies_immediately.md)
- [EOP-003-put_deleted_entry_ies_back](../EOP-003-manage_entry_lifecycle/EOP-003-put_deleted_entry_ies_back.md)
- [EOP-003-empty_trash](../EOP-003-manage_entry_lifecycle/EOP-003-empty_trash.md)
- [EOP-003-undo_entry_action](../EOP-003-manage_entry_lifecycle/EOP-003-undo_entry_action.md)
- [EOP-003-redo_entry_action](../EOP-003-manage_entry_lifecycle/EOP-003-redo_entry_action.md)
- [EOP-004-rename_entry](../EOP-004-edit_entry_metadata/EOP-004-rename_entry.md)
- [EOP-004-edit_entry_ies_tags](../EOP-004-edit_entry_metadata/EOP-004-edit_entry_ies_tags.md)
- [EOP-004-get_entry_info](../EOP-004-edit_entry_metadata/EOP-004-get_entry_info.md)
- [EOP-004-change_entry_permission_s](../EOP-004-edit_entry_metadata/EOP-004-change_entry_permission_s.md)
- [EOP-004-batch_rename_entries](../EOP-004-edit_entry_metadata/EOP-004-batch_rename_entries.md)
- [EOP-006-copy_absolute_path_s_of_entry_ies](../EOP-006-copy_entry_references/EOP-006-copy_absolute_path_s_of_entry_ies.md)
- [EOP-006-copy_releative_path_s_of_entry_ies](../EOP-006-copy_entry_references/EOP-006-copy_releative_path_s_of_entry_ies.md)
- [EOP-006-copy_urls_of_entry_ies](../EOP-006-copy_entry_references/EOP-006-copy_urls_of_entry_ies.md)

## Flow Overview

```mermaid
flowchart TD
  A1[Open Entry with Default App] --> A2[Open Entry with Selected App]
  A2[Open Entry with Selected App] --> A3[Set Default App for Entry]
  A3[Set Default App for Entry] --> A4[Quick Look Entry]
  A4[Quick Look Entry] --> A5[Create New Folder]
  A5[Create New Folder] --> A6[Copy Entry(ies)]
  A6[Copy Entry(ies)] --> A7[Cut Entry(ies)]
  A7[Cut Entry(ies)] --> A8[Paste Entry(ies)]
  A8[Paste Entry(ies)] --> A9[Duplicate Entry(ies)]
  A9[Duplicate Entry(ies)] --> A10[Move Entry(ies)]
  A10[Move Entry(ies)] --> A11[Create Entry Alias]
  A11[Create Entry Alias] --> A12[Compress Entry(ies)]
  A12[Compress Entry(ies)] --> A13[Extract Compressed File(s)]
  A13[Extract Compressed File(s)] --> A14[Move Entry(ies) to Trash]
  A14[Move Entry(ies) to Trash] --> A15[Delete Entry(ies) Immediately]
  A15[Delete Entry(ies) Immediately] --> A16[Put Deleted Entry(ies) Back]
  A16[Put Deleted Entry(ies) Back] --> A17[Empty Trash]
  A17[Empty Trash] --> A18[Undo Entry Action]
  A18[Undo Entry Action] --> A19[Redo Entry Action]
  A19[Redo Entry Action] --> A20[Rename Entry]
  A20[Rename Entry] --> A21[Edit Entry(ies) Tags]
  A21[Edit Entry(ies) Tags] --> A22[Get Entry Info]
  A22[Get Entry Info] --> A23[Change Entry Permission(s)]
  A23[Change Entry Permission(s)] --> A24[Batch Rename Entries]
  A24[Batch Rename Entries] --> A25[Copy Absolute Path(s) of Entry(ies)]
  A25[Copy Absolute Path(s) of Entry(ies)] --> A26[Copy Releative Path(s) of Entry(ies)]
  A26[Copy Releative Path(s) of Entry(ies)] --> A27[Copy URL(s) of Entry(ies)]
```

## Happy Path

1. [EOP-001-open_entry_with_default_app](../EOP-001-execute_entry/EOP-001-open_entry_with_default_app.md)는 해당 Entry를 기본 앱으로 실행 흐름을 담당한다.
2. [EOP-001-open_entry_with_selected_app](../EOP-001-execute_entry/EOP-001-open_entry_with_selected_app.md)는 선택한 Entry를 사용자가 지정한 앱으로 실행 흐름을 담당한다.
3. [EOP-001-set_default_app_for_entry](../EOP-001-execute_entry/EOP-001-set_default_app_for_entry.md)는 선택한 Entry의 파일 유형에 대해 기본 실행 앱을 설정 흐름을 담당한다.
4. [EOP-001-quick_look_entry](../EOP-001-execute_entry/EOP-001-quick_look_entry.md)는 선택한 Entry의 내용을 볼 수 있는 Quick Look을 실행 흐름을 담당한다.
5. [EOP-002-create_new_folder](../EOP-002-arrange_entries/EOP-002-create_new_folder.md)는 현재 디렉토리에 새 폴더를 생성하고 곧바로 이름 편집 모드로 진입 흐름을 담당한다.
6. [EOP-002-copy_entry_ies](../EOP-002-arrange_entries/EOP-002-copy_entry_ies.md)는 선택한 Entry를 클립보드에 복사 흐름을 담당한다.
7. [EOP-002-cut_entry_ies](../EOP-002-arrange_entries/EOP-002-cut_entry_ies.md)는 선택한 Entry를 이동을 위한 잘라내기 상태로 클립보드에 저장 흐름을 담당한다.
8. [EOP-002-paste_entry_ies](../EOP-002-arrange_entries/EOP-002-paste_entry_ies.md)는 클립보드에 저장된 Entry를 현재 디렉토리에 붙여넣기 흐름을 담당한다.
9. [EOP-002-duplicate_entry_ies](../EOP-002-arrange_entries/EOP-002-duplicate_entry_ies.md)는 선택한 Entry의 복제본을 동일 위치에 생성 흐름을 담당한다.
10. [EOP-002-move_entry_ies](../EOP-002-arrange_entries/EOP-002-move_entry_ies.md)는 선택한 Entry를 지정한 대상 디렉토리로 이동 흐름을 담당한다.
11. [EOP-002-create_entry_alias](../EOP-002-arrange_entries/EOP-002-create_entry_alias.md)는 선택한 Entry에 대한 Alias(바로가기)를 생성 흐름을 담당한다.
12. [EOP-002-compress_entry_ies](../EOP-002-arrange_entries/EOP-002-compress_entry_ies.md)는 선택한 Entry를 현재 디렉토리에 하나의 압축 파일로 생성 흐름을 담당한다.
13. [EOP-002-extract_compressed_file_s](../EOP-002-arrange_entries/EOP-002-extract_compressed_file_s.md)는 선택한 압축 파일을 현재 디렉토리 또는 지정한 위치로 해제 흐름을 담당한다.
14. [EOP-003-move_entry_ies_to_trash](../EOP-003-manage_entry_lifecycle/EOP-003-move_entry_ies_to_trash.md)는 선택한 Entry를 휴지통으로 이동 흐름을 담당한다.
15. [EOP-003-delete_entry_ies_immediately](../EOP-003-manage_entry_lifecycle/EOP-003-delete_entry_ies_immediately.md)는 선택한 Entry를 휴지통을 거치지 않고 즉시 영구 삭제 흐름을 담당한다.
16. [EOP-003-put_deleted_entry_ies_back](../EOP-003-manage_entry_lifecycle/EOP-003-put_deleted_entry_ies_back.md)는 선택한 휴지통의 Entry를 휴지통으로 가기 이전 경로로 복원 흐름을 담당한다.
17. [EOP-003-empty_trash](../EOP-003-manage_entry_lifecycle/EOP-003-empty_trash.md)는 휴지통에 있는 모든 Entry를 영구 삭제 흐름을 담당한다.
18. [EOP-003-undo_entry_action](../EOP-003-manage_entry_lifecycle/EOP-003-undo_entry_action.md)는 최근 수행한 Entry 관련 액션을 되돌림 흐름을 담당한다.
19. [EOP-003-redo_entry_action](../EOP-003-manage_entry_lifecycle/EOP-003-redo_entry_action.md)는 Undo로 되돌린 최근 Entry 관련 액션을 다시 적용 흐름을 담당한다.
20. [EOP-004-rename_entry](../EOP-004-edit_entry_metadata/EOP-004-rename_entry.md)는 선택한 Entry의 이름을 편집해 변경 흐름을 담당한다.
21. [EOP-004-edit_entry_ies_tags](../EOP-004-edit_entry_metadata/EOP-004-edit_entry_ies_tags.md)는 선택한 Entry의 태그(라벨/색)를 추가·제거·변경 흐름을 담당한다.
22. [EOP-004-get_entry_info](../EOP-004-edit_entry_metadata/EOP-004-get_entry_info.md)는 선택한 Entry의 상세 정보 패널을 표시 흐름을 담당한다.
23. [EOP-004-change_entry_permission_s](../EOP-004-edit_entry_metadata/EOP-004-change_entry_permission_s.md)는 선택한 Entry의 읽기·쓰기·실행 권한과 소유자/그룹을 수정 흐름을 담당한다.
24. [EOP-004-batch_rename_entries](../EOP-004-edit_entry_metadata/EOP-004-batch_rename_entries.md)는 선택한 여러 Entry의 이름에 패턴·번호 매김·문자열 치환 규칙을 적용해 일괄적으로 변경 흐름을 담당한다.
25. [EOP-006-copy_absolute_path_s_of_entry_ies](../EOP-006-copy_entry_references/EOP-006-copy_absolute_path_s_of_entry_ies.md)는 선택한 Entry의 절대 경로를 클립보드에 복사 흐름을 담당한다.
26. [EOP-006-copy_releative_path_s_of_entry_ies](../EOP-006-copy_entry_references/EOP-006-copy_releative_path_s_of_entry_ies.md)는 선택한 Entry의 현재 디렉토리를 기준으로 한 상대 경로를 클립보드에 복사 흐름을 담당한다.
27. [EOP-006-copy_urls_of_entry_ies](../EOP-006-copy_entry_references/EOP-006-copy_urls_of_entry_ies.md)는 선택한 Entry의 파일 시스템 URL을 클립보드에 복사 흐름을 담당한다.

## Alternate Paths

- 사용자가 이미 적용된 상태를 다시 호출하면, 앱은 중복 상태 변경을 만들지 않고 현재 상태를 유지한다.
- 대상 Entry, Page, selection, 권한, 파일 시스템 조건이 유효하지 않으면 상태를 부분 반영하지 않고 실패 피드백을 표시한다.
- background interaction은 사용자의 현재 포커스와 명시적 selection을 보존하면서 최신 상태만 갱신한다.

## Boundary Notes

- 이 flow는 EOP category의 공통 contract 상태 어휘를 기준으로 interaction 순서와 책임을 정리한다.
- Covered features는 `EOP-001 Execute Entry`, `EOP-002 Arrange Entries`, `EOP-003 Manage Entry Lifecycle`, `EOP-004 Edit Entry Metadata`, `EOP-006 Copy Entry References`이다.
- 구현 세부 이벤트 순서보다 사용자에게 보이는 Page, Entry, selection, action 결과를 우선한다.

## Source

- Category: `EOP`
- Related contract: [eop_contract.toml](../contracts/eop_contract.toml)
