# Restore Saved Collection Snapshot

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-002-restore_saved_collection_snapshot |
| Interaction Type | background |
| Feature | Manage Retrieval Collections |
| Category Key | RCL |
| Feature ID | RCL-002 |
| Status | 기획 완료 |
| Summary | 저장된 콜렉션을 다시 열 때 definition과 persisted snapshot/meta를 함께 읽고, usable snapshot인지 판단해 초기 복원 경로를 결정 |
| Related Region | file_manager_window.content_pane.page_container.page_mode_collection |
| Menu | - |
| Shortcut | - |

## Preconditions

- 저장된 콜렉션을 여는 흐름이 시작된 상태
- 저장된 콜렉션 정의를 읽을 수 있고, persisted snapshot/meta의 usable 여부를 판단할 수 있는 상태

## Edge Cases

- snapshot은 있으나 snapshotMeta가 없어 usable하지 않은 경우
- snapshot과 definition fingerprint가 일치하지 않아 hydrate를 건너뛰어야 하는 경우
- definition은 유효하지만 snapshot이 unusable하여 fallback search로 전환되는 경우

## Acceptance Criteria

- [ ] 저장된 콜렉션을 다시 열 때, 시스템은 검색 조건(definition)과 persisted snapshot/meta를 함께 읽어 복원 경로를 판단함
- [ ] 시스템은 snapshot, snapshotMeta, 그리고 fingerprint 일치 조건을 모두 만족할 때만 snapshot을 usable하다고 판단함
- [ ] usable snapshot이 있으면, 시스템은 결과를 즉시 확인할 수 있는 초기 상태를 먼저 구성함
- [ ] snapshot이 usable하지 않다면, 시스템은 snapshot-first 복원을 중단하고 definition-first search fallback으로 전환함
- [ ] freshness 판단에 필요한 메타데이터가 없으면 snapshot을 그대로 신뢰하지 않으며, stale 판단 이전에 snapshot을 unusable로 처리함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `130`
