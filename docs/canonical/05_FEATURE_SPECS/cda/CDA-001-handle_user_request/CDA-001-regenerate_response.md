# Regenerate Response

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CDA-001-regenerate_response |
| Interaction Type | command |
| Feature | Handle User Request |
| Category Key | CDA |
| Feature ID | CDA-001 |
| Status | 기획 완료 |
| Summary | 특정 User Request Message에 대해 응답을 재생성하도록 새 생성 Run을 시작하고, 기존 응답은 버전으로 보존 |
| Related Region | file_manager_window.inspector_pane.inspector_mode_chat |
| Menu | - |
| Shortcut | - |

## Preconditions

- <<AI>> 대상 Message에 Assistant Response가 존재하는 상태
## Edge Cases

- <<AI>> 기존 스트리밍이 진행 중인 경우
- <<AI>> 연속 재호출하는 경우

## Acceptance Criteria

- [ ] <<AI>> 응답이 존재할 때, 사용자가 호출하면, 기존 응답은 이전 버전으로 유지되고 새 응답 생성이 시작됨.
- [ ] <<AI>> 생성 중 재호출하면, 중복 실행이 방지되고 마지막 요청만 유효하게 처리됨.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `147`
