# Stream Processing Message

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CDA-001-stream_processing_message |
| Interaction Type | display |
| Feature | Handle User Request |
| Category Key | CDA |
| Feature ID | CDA-001 |
| Status | 기획 완료 |
| Summary | 대상 User Request Message에 대한 응답을 토큰 또는 청크 단위로 Chat Pane에 점진적으로 표시함 |
| Related Region | file_manager_window.inspector_pane.inspector_mode_chat |
| Menu | - |
| Shortcut | - |

## Preconditions

- 대상 User Request Message가 처리 중인 상태
## Edge Cases

- Cancel Processing Message 인터랙션이 호출되는 경우
- 네트워크 오류로 응답 수신이 중단되는 경우

## Acceptance Criteria

- [ ] 유저가 Submit Message 호출이 정상적으로 처리되었을 때, 시스템이 해당 인터랙션을 실행하면, 응답 텍스트가 토큰 또는 청크 단위로 점진적으로 표시됨
- [ ] 대상 User Request Message가 처리 중인 상태일 때, 사용자가 Cancel Processing Message를 호출하면, 추가 토큰이 표시되지 않고 스트리밍이 즉시 종료됨
- [ ] 대상 User Request Message가 처리 중인 상태일 때, 네트워크 오류가 발생한다면, 이미 수신된 부분 응답까지만 표시되고 오류 상태가 함께 표시됨

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `145`
