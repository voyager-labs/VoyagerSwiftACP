# Show Retrieval Results

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CDA-003-show_retrieval_results |
| Interaction Type | display |
| Feature | Handle Retrieve Intent |
| Category Key | CDA |
| Feature ID | CDA-003 |
| Status | 기획 완료 |
| Summary | TBD |
| Related Region | file_manager_window.inspector_pane.inspector_mode_chat |
| Menu | - |
| Shortcut | - |

## Preconditions

- 현재 대화에서 Retrieve Intent에 대한 응답이 완료된 상태
- Inspector Pane이 Chat 모드로 표시된 상태
## Edge Cases

- <<AI>> 검색 결과가 너무 많아 페이지네이션 또는 ‘더 보기’ 인터랙션이 필요한 경우
- <<AI>> 사용자 컨텍스트가 이미 다른 범위로 변경된 후 늦게 도착한 결과를 표시해야 하는 경우
- <<AI>> 동일 대화 내 여러 Retrieve Intent 결과가 섞여 있는 경우

## Acceptance Criteria

- [ ] <<AI>> 현재 User Request에 대한 Retrieval 결과 세트가 존재하는 상태일 때, 시스템이 Show Retrieval Results 인터랙션을 실행하면, 해당 결과가 Chat 결과 영역에 하나의 그룹으로 표시됨.
- [ ] <<AI>> Retrieval 결과가 0건인 상태일 때, 시스템이 Show Retrieval Results 인터랙션을 실행하면, ‘결과 없음’ 메시지와 함께 현재 검색 범위나 필터 정보를 요약해 표시됨.
- [ ] <<AI>> 동일 대화 안에 여러 Retrieve Intent 결과가 존재하는 상태일 때, 시스템이 Show Retrieval Results 인터랙션을 실행하면, 각 User Request별로 결과 그룹이 구분되어 표시됨.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `162`
