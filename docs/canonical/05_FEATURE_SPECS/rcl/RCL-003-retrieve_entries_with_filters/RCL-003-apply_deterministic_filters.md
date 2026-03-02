# Apply Deterministic Filters

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-003-apply_deterministic_filters |
| Interaction Type | background |
| Feature | Retrieve Entries with Filters |
| Category Key | RCL |
| Feature ID | RCL-003 |
| Status | 배포 완료 |
| Summary | 콜렉션 스코프와 시스템·커스텀 프로퍼티 조건을 결정론적으로 평가해 후보 entry 집합을 산출하고, 조건 불일치 entry를 제외 |
| Related Region | - |
| Menu | - |
| Shortcut | - |

## Preconditions

- 실행할 필터 스냅샷이 확정된 상태
## Edge Cases

- 인덱스가 최신 상태가 아니어서 일부 엔트리가 인덱스에는 존재하지만 실제 파일 시스템에서는 이동되었거나 삭제된 상태인 경우
- 인덱싱이 아직 완료되지 않아 일부 엔트리 또는 일부 메타데이터 필드가 인덱스에 누락된 상태인 경우
- OS 인덱싱 기반 검색으로 보강을 시도했지만 실패하는 경우

## Acceptance Criteria

- [ ] 검색 파이프라인이 시작될 때, 실행할 필터 스냅샷이 확정이 되어있다면, 해당 필터 정의를 기준으로 후보 엔트리 집합을 산출함
- [ ] 검색 파이프라인이 시작될 때, 미완성 컨디션이 포함되어 있다면, 해당 컨디션은 필터에서 제외한 스냅샷으로 검색을 진행함
- [ ] 필터 정의를 기준으로 후보를 산출할 때, 인덱스 상 엔트리가 실제 파일 시스템에서 이동되었거나 삭제된 것이 확인되면, 해당 엔트리를 후보 집합에서 제외함
- [ ] 필터 정의를 기준으로 후보를 산출할 때, 인덱싱 누락으로 일부 엔트리 또는 일부 메타데이터 필드가 인덱스에 없다면, OS 인덱싱 기반 검색으로 보강을 시도하고 보강 결과를 기준으로 후보 산출을 계속함
- [ ] 필터 정의를 기준으로 후보를 산출할 때, OS 인덱싱 기반 검색으로 보강을 시도했지만 실패했다면, 해당 엔트리는 후보 집합에서 제외함

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `133`
