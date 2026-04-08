# Open Saved Collection

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-002-open_saved_collection |
| Interaction Type | command |
| Feature | Manage Retrieval Collections |
| Category Key | RCL |
| Feature ID | RCL-002 |
| Status | 기획 완료 |
| Summary | 저장된 콜렉션을 열고, usable snapshot이 있으면 snapshot-first 복원을 시작하고 그렇지 않으면 definition-first search fallback으로 전환 |
| Related Region | file_manager_window.content_pane.page_container.page_mode_collection |
| Menu | - |
| Shortcut | - |

## Preconditions

- 저장된 콜렉션 파일 또는 목록 항목이 존재하는 상태
- 사용자가 해당 콜렉션을 다시 열 수 있는 경로와 권한이 확보된 상태

## Edge Cases

- snapshot은 존재하지만 usable하지 않은 경우
- unsupported filter가 포함되어 있지만 나머지 정의로 open 가능한 경우
- 파일 decode 자체가 실패하거나 정의가 비어 있어 open을 계속할 수 없는 경우
- 동일 콜렉션이 다른 탭 또는 윈도우에 열려 있어도 현재 open 요청은 별도로 처리되는 경우

## Acceptance Criteria

- [ ] 사용자가 저장된 콜렉션을 열면, 시스템은 해당 콜렉션 페이지를 열고 snapshot-first 복원 흐름을 시작함
- [ ] usable snapshot이 있으면, 시스템은 다시 열 때마다 즉시 재검색하지 않고 저장된 결과를 먼저 보여주는 흐름을 우선 적용함
- [ ] usable snapshot이 없다면, 시스템은 정의 기반 검색 fallback으로 전환해 콜렉션을 열 수 있게 함
- [ ] snapshot 또는 snapshot metadata가 없거나 usable하지 않은 경우만으로 open을 실패로 처리하지 않으며, 가능한 경우 definition-first fallback으로 계속 진행함
- [ ] 콜렉션 파일 자체가 손상되었거나 정의를 복원할 수 없으면, 시스템은 실패를 안내하고 화면 상태를 일관되게 유지함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `129`
