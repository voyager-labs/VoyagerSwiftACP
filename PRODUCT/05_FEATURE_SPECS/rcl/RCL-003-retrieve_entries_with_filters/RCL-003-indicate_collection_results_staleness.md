# Indicate Collection Results Staleness

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-003-indicate_collection_results_staleness |
| Interaction Type | display |
| Feature | Retrieve Entries with Filters |
| Category Key | RCL |
| Feature ID | RCL-003 |
| Status | 아이디어 |
| Summary | 현재 콜렉션 결과가 stale 상태일 때, 사용자가 최신성이 보장되지 않음을 인지할 수 있도록 collection title affordance 영역에 상태를 표시하도록 함 |
| Related Region | file_manager_window.content_pane.content_header |
| Menu | - |
| Shortcut | - |

## Preconditions

- 현재 콜렉션 결과가 stale 상태로 판단된 상태
- 사용자가 현재 콜렉션 페이지를 보고 있는 상태

## Edge Cases

- stale 상태지만 아직 usable snapshot 결과를 표시 중인 경우
- stale가 해제되기 전 사용자가 수동 refresh를 여러 번 시도하는 경우
- dirty 표시와 stale 표시가 함께 존재하는 경우
- 현재 브랜치에서는 stale 표시 UI affordance가 아직 미구현이라 이후 UI task에서 구체화되어야 하는 경우

## Acceptance Criteria

- [ ] 현재 콜렉션 결과가 stale 상태이면, 시스템은 사용자가 freshness가 보장되지 않음을 인지할 수 있는 stale 표시를 노출하도록 함
- [ ] 시스템은 stale 표시를 dirty 표시와 구분해, save 가능 여부와 최신성 여부가 다른 의미임을 유지함
- [ ] usable snapshot 결과를 표시 중인 경우라도 stale 상태라면, 시스템은 사용자가 현재 결과를 최신 결과로 오인하지 않도록 stale 상태를 유지해 전달함
- [ ] refresh 성공 시 stale가 해제되면, 시스템은 stale 표시를 제거하거나 최신 상태에 맞게 갱신함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `145`
