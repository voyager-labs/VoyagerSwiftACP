# Retry Selected Indexing Failure

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EIX-002-retry_selected_indexing_failure |
| Interaction Type | command |
| Feature | Monitor Indexing Status |
| Category Key | EIX |
| Feature ID | EIX-002 |
| Status | 준비 완료 |
| Summary | 선택한 인덱싱 실패 항목의 인덱싱을 재시도 |
| Related Region | file_manager_window.sidebar.sidebar_footer |
| Menu | - |
| Shortcut | - |

## Preconditions

- 인덱싱 실패 항목이 선택된 상태
## Edge Cases

- 실패 원인이 지속되어 재시도가 반복 실패하는 경우
- 대상 엔트리가 삭제되었거나 경로가 변경되어 재시도가 불가능한 경우

## Acceptance Criteria

- [ ] 인덱싱 실패 항목이 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 시스템이 선택한 실패 항목을 재시도 작업으로 등록하고 항목 상태를 재시도 진행 상태로 갱신함
- [ ] 실패 항목 인덱싱 재시도를 했을 때, 실패 원인이 지속되어 재시도가 반복 실패한다면, 실패 상태를 유지하고 오류 요약을 최신 정보로 갱신함
- [ ] 실패 항목 인덱싱 재시도를 했을 때, 대상 엔트리가 삭제되었거나 경로가 변경되어 재시도가 불가능하다면, 재시도 불가 사유를 기록하고 항목 상태를 실패로 유지함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `77`
