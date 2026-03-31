# Show Organize Commands Preview

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CDA-004-show_organize_commands_preview |
| Interaction Type | display |
| Feature | Handle Organize Intent |
| Category Key | CDA |
| Feature ID | CDA-004 |
| Status | 기획 완료 |
| Summary | 생성된 정돈 명령이 파일 시스템에 미칠 영향을 사용자에게 요약/프리뷰로 제공 |
| Related Region | file_manager_window.inspector_pane.inspector_mode_chat |
| Menu | - |
| Shortcut | - |

## Preconditions

- 현재 대화에서 Organize Intent에 대한 명령이 하나 이상 생성된 상태
- Inspector Pane이 Chat 모드로 표시된 상태
## Edge Cases

- <<AI>> 명령 개수가 매우 많아 전체를 한 번에 표시하기 어려운 경우
- <<AI>> 일부 명령의 영향 범위를 계산할 수 없는 경우
- <<AI>> 프리뷰 표시 후 User Request가 변경되어 기존 프리뷰가 무효화되는 경우

## Acceptance Criteria

- [ ] <<AI>> 유효한 Organize Commands 목록이 존재하는 상태일 때, 시스템이 Show Organize Commands Preview 인터랙션을 실행하면, 각 명령의 대상과 수행 액션 및 예상 결과가 프리뷰 형태로 표시됨.
- [ ] <<AI>> 위험 플래그가 설정된 명령이 포함된 상태일 때, 시스템이 Show Organize Commands Preview 인터랙션을 실행하면, 해당 명령이 시각적으로 강조되어 사용자에게 추가 주의를 요청함.
- [ ] <<AI>> 프리뷰가 표시된 이후 User Request가 변경된 상태일 때, 시스템이 Show Organize Commands Preview 인터랙션을 다시 실행하면, 이전 프리뷰가 무효화되고 최신 Request 기준으로 생성된 프리뷰가 표시됨.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `164`
