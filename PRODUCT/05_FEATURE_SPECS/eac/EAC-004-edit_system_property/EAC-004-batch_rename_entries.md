# Batch Rename Entries

## Metadata

| Field            | Value                                                                               |
| ---------------- | ----------------------------------------------------------------------------------- |
| Interaction ID   | EAC-004-batch_rename_entries                                                        |
| Interaction Type | command                                                                             |
| Feature          | Edit System Property                                                                |
| Category Key     | EAC                                                                                 |
| Feature ID       | EAC-004                                                                             |
| Status           | 준비 완료                                                                           |
| Summary          | 선택한 여러 Entry의 이름에 패턴·번호 매김·문자열 치환 규칙을 적용해 일괄적으로 변경 |
| Related Region   | file_manager_window.content_pane.page_container.page_mode_directory                 |
| Menu             | File                                                                                |
| Shortcut         | -                                                                                   |

## Preconditions

- <<AI>> 두 개 이상의 Entry가 선택된 상태
- <<AI>> 선택된 Entry들에 대해 이름 변경을 적용할 수 있는 상태

## Edge Cases

- <<AI>> 규칙 적용 결과가 중복 이름을 생성하는 경우
- <<AI>> 규칙 적용 결과가 유효하지 않은 파일명을 생성하는 경우
- <<AI>> 일부 Entry만 권한 문제로 변경 불가능한 경우
- <<AI>> 사용자가 적용을 취소하는 경우

## Acceptance Criteria

- [ ] <<AI>> 두 개 이상의 Entry가 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 배치 이름
      변경 규칙 설정 및 결과 미리보기를 제공함.
- [ ] <<AI>> 규칙이 확정된 상태일 때, 사용자가 적용하면, 선택된 Entry들의 이름을 규칙에 따라 일괄
      변경함.
- [ ] <<AI>> 적용이 취소되거나 적용 불가한 상태일 때, 사용자가 종료하면, 이름 변경을 수행하지 않도록
      함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `62`
