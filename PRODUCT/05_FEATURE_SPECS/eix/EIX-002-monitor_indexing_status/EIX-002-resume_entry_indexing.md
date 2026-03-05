# Resume Entry Indexing

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EIX-002-resume_entry_indexing |
| Interaction Type | command |
| Feature | Monitor Indexing Status |
| Category Key | EIX |
| Feature ID | EIX-002 |
| Status | 준비 완료 |
| Summary | 일시 중지된 엔트리 인덱싱 작업을 재개 |
| Related Region | file_manager_window.sidebar.sidebar_footer |
| Menu | - |
| Shortcut | - |

## Preconditions

- 엔트리 인덱싱이 일시 중지된 상태
## Edge Cases

- 재개 시점에 스토리지 연결 해제 또는 권한 문제로 델타 스캔이 불완전한 경우
- 재개 시점에 변경분이 매우 많아 큐 처리가 지연되는 경우

## Acceptance Criteria

- [ ] 엔트리 인덱싱이 일시 중지된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 시스템이 일시 중지를 해제하고 인덱싱 큐의 처리를 재개함
- [ ] 엔트리 인덱싱을 재개할 때, 시스템이 델타 스캔을 수행하면, 마지막 인덱싱 기준 이후 변경된 엔트리를 수집해 인덱싱 큐에 반영함
- [ ] 재개 시점에 스토리지 연결 해제 또는 권한 문제로 델타 스캔이 불완전한 경우일 때, 시스템이 델타 스캔 결과를 반영하면, 접근 가능한 범위의 변경분만 큐에 반영하고 접근 불가 범위는 실패 또는 누락으로 기록함
- [ ] 재개 시점에 변경분이 매우 많아 큐 처리가 지연되는 경우일 때, 시스템이 인덱싱 큐를 처리하면, 작업을 배치로 분할하고 처리량을 제어하면서 진행 상태를 갱신함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `75`
