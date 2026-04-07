# Invalidate Closed Collection Staleness on External Change

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-003-invalidate_closed_collection_staleness_on_external_change |
| Interaction Type | background |
| Feature | Retrieve Entries with Filters |
| Category Key | RCL |
| Feature ID | RCL-003 |
| Status | 기획 완료 |
| Summary | helper가 유지한 changed-path replay를 앱이 소비해, 닫혀 있는 등록된 콜렉션의 stale invalidation record를 갱신하고 다음 reopen 시 최신성 판단이 가능하게 함 |
| Related Region | - |
| Menu | - |
| Shortcut | - |

## Preconditions

- 저장된 콜렉션이 현재 닫혀 있어 열린 Content View를 가지지 않는 상태
- 외부 파일시스템 변경 신호가 해당 콜렉션의 scope 아래 경로와 관련된 상태
- stale invalidation 대상 콜렉션이 이미 register된 상태
- 앱이 helper replay 또는 브리지된 changed paths를 소비해 stale 판단 기록을 갱신할 수 있는 상태

## Edge Cases

- 여러 개의 닫힌 콜렉션이 동일 경로 범위를 공유해 동시에 stale invalidation 대상이 되는 경우
- 메인 앱이 꺼져 있는 동안 helper가 유지한 changed-path replay가 앱 재활성화 후 한꺼번에 소비되는 경우
- 콜렉션 scope가 넓어 하나의 변경이 많은 저장된 콜렉션에 영향을 주는 경우
- 아직 register되지 않은 콜렉션은 invalidation 대상에 포함되지 않는 경우
- 콜렉션 정의가 이미 삭제되었거나 이동되어 stale 기록 대상을 찾을 수 없는 경우

## Acceptance Criteria

- [ ] 닫혀 있는 등록된 콜렉션의 scope 아래 경로에서 외부 파일시스템 변경이 발생하면, 시스템은 열린 Content View 존재 여부와 무관하게 앱이 changed paths를 소비해 CollectionStalenessClient의 persisted invalidation record를 갱신함
- [ ] 여러 닫힌 등록된 콜렉션이 동일 변경 경로의 영향을 받으면, 시스템은 각 콜렉션의 stale invalidation을 누락 없이 기록함
- [ ] 메인 앱이 꺼져 있는 동안 발생한 변경이라도, helper가 유지한 changed-path replay가 앱 재활성화 후 소비되어 다음 reopen 시 stale 판단으로 이어질 수 있게 함
- [ ] 아직 register되지 않은 콜렉션은 stale invalidation record 갱신 대상에 포함되지 않음
- [ ] stale invalidation 대상을 찾을 수 없는 경우, 시스템은 다른 콜렉션 기록 처리까지 중단하지 않고 가능한 범위의 invalidation을 계속 수행함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `148`
