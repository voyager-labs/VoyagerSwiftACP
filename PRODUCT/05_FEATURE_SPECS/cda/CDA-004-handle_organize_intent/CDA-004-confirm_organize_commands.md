# Confirm Organize Commands

## Metadata

| Field            | Value                                                          |
| ---------------- | -------------------------------------------------------------- |
| Interaction ID   | CDA-004-confirm_organize_commands                              |
| Interaction Type | command                                                        |
| Feature          | Handle Organize Intent                                         |
| Category Key     | CDA                                                            |
| Feature ID       | CDA-004                                                        |
| Status           | 기획 완료                                                      |
| Summary          | 사용자가 정돈 명령어 프리뷰를 확인 후 실행 승인 및 거절을 선택 |
| Related Region   | file_manager_window.inspector_pane.inspector_mode_chat         |
| Menu             | -                                                              |
| Shortcut         | -                                                              |

## Preconditions

- <<AI>> 처리 중인 Message가 Organize Intent를 포함하는 상태
- <<AI>> Organize Commands 프리뷰가 화면에 표시된 상태임
- <<AI>> 실행 가능한 Organize Command가 하나 이상 존재함
- <<AI>> 현재 사용자에게 대상 entry에 대한 수정 권한이 있음

## Edge Cases

- <<AI>> 사용자가 승인 또는 거절 버튼을 빠르게 연속 클릭하는 경우
- <<AI>> 승인 직전에 대상 entry가 외부 요인으로 변경되거나 삭제되는 경우
- <<AI>> 프리뷰가 표시된 탭이나 창이 승인 과정 중에 닫히는 경우

## Acceptance Criteria

- [ ] <<AI>> Organize Commands 프리뷰가 표시된 상태일 때, 사용자가 Confirm Organize Commands
      인터랙션에서 실행을 승인하면, 승인된 명령 목록이 Execute Organize Commands 단계로 한 번만
      전달됨.
- [ ] <<AI>> Organize Commands 프리뷰가 표시된 상태일 때, 사용자가 Confirm Organize Commands
      인터랙션에서 실행을 거절하면, 어떤 명령도 실행되지 않고 프리뷰가 닫힘.
- [ ] <<AI>> 같은 User Request에 대해 사용자가 Confirm Organize Commands 인터랙션을 반복 호출한
      상태일 때, 시스템이 후속 호출을 처리하면, 첫 승인 또는 거절 결과만 유효하게 유지되고 중복
      요청은 무시됨.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `166`
