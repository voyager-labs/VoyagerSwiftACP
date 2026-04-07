# Reindex All Entries

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EIX-001-reindex_all_entries |
| Interaction Type | background |
| Feature | Index Entries |
| Category Key | EIX |
| Feature ID | EIX-001 |
| Status | 준비 완료 |
| Summary | 워크스페이스 전체에 대해 내용 기반 프로퍼티·임베딩 인덱스를 다시 실행해 손상되었거나 오래된 인덱스를 초기화·복구 |
| Related Region | - |
| Menu | - |
| Shortcut | - |

## Preconditions

- Entry Indexing 진행이 일시 중지되지 않은 상태
- 전체 재인덱싱 작업이 이미 진행 중이지 않은 상태
## Edge Cases

- 스토리지 연결 해제 또는 권한 철회로 대상 일부가 접근 불가가 되는 경우
- 인덱스 저장소 손상 또는 스키마 마이그레이션 등으로 재생성이 필요한 경우
- 디스크 공간·메모리 부족으로 일부 단계가 실패하는 경우

## Acceptance Criteria

- [ ] 엔트리 인덱싱 진행이 일시 중지되지 않은 상태일 때, 시스템이 전체 재인덱싱을 시작하면, 인덱싱 대상으로 설정된 전체 스토리지 범위를 재스캔하고 시스템·콘텐츠·임베딩 인덱스를 새 실행으로 재생성함
- [ ] 전체 재인덱싱 작업이 이미 진행 중이지 않은 상태일 때, 시스템이 재인덱싱을 시작하면, 중복 실행을 만들지 않고 단일 실행으로 진행 상태를 기록함
- [ ] 시스템이 재인덱싱이 수행 중일 때, 스토리지 연결 해제 또는 권한 철회로 대상 일부가 접근 불가가 된다면, 접근 가능한 범위는 처리하고 접근 불가 항목은 실패로 기록함
- [ ] 시스템이 재인덱싱을 완료했을 때, 인덱스 저장소 손상 또는 스키마 마이그레이션 등으로 재생성이 필요하다면, 새 인덱스로 스위치오버해 손상/구버전 인덱스를 복구함
- [ ] 시스템이 재인덱싱을 수행 중일 때, 디스크 공간·메모리 부족으로 일부 단계가 실패한다면, 실패 항목을 기록하고 가능한 범위의 처리는 계속함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `72`
