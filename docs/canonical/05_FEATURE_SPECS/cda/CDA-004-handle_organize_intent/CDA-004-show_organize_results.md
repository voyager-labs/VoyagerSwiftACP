# Show Organize Results

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CDA-004-show_organize_results |
| Interaction Type | display |
| Feature | Handle Organize Intent |
| Category Key | CDA |
| Feature ID | CDA-004 |
| Status | 기획 완료 |
| Summary | 실행 완료된 Oragnize Intent Response를 Chat Pane에 표시 |
| Related Region | file_manager_window.inspector_pane.inspector_mode_chat |
| Menu | - |
| Shortcut | - |

## Preconditions

- <<AI>> 처리 중인 Message가 Organize Intent를 포함하는 상태
- <<AI>> 현재 대화에서 Organize Commands 실행 결과 기록이 존재함
- <<AI>> Inspector Pane이 Chat 모드로 표시되어 있음
- <<AI>> 결과를 표시할 수 있는 UI 영역이 렌더링된 상태임
## Edge Cases

- <<AI>> Organize 실행 결과가 매우 많아 한 번에 표시하기 어려운 경우
- <<AI>> Organize 실행 후 entry가 외부 요인으로 다시 변경되거나 삭제된 경우
- <<AI>> 서로 다른 User Request에서 실행된 Organize 결과가 섞여 있는 경우

## Acceptance Criteria

- [ ] <<AI>> 현재 대화에서 Organize 실행 기록이 존재하는 상태일 때, 시스템이 Show Organize Results 인터랙션을 실행하면, 해당 실행 결과만 시간 순으로 결과 영역에 표시됨.
- [ ] <<AI>> Organize 실행 결과가 매우 많은 상태일 때, 시스템이 Show Organize Results 인터랙션을 실행하면, 스크롤 또는 페이지네이션 등을 사용해 결과가 나누어 표시됨.
- [ ] <<AI>> Organize 실행 후 entry가 외부 요인으로 다시 변경된 상태일 때, 시스템이 Show Organize Results 인터랙션을 실행하면, 원래 실행 결과와 현재 상태가 명확히 구분되어 표시됨.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `168`
