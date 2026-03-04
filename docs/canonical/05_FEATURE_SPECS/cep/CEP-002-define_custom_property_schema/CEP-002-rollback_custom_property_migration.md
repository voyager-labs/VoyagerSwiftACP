# Rollback Custom Property Migration

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CEP-002-rollback_custom_property_migration |
| Interaction Type | command |
| Feature | Define Custom Property Schema |
| Category Key | CEP |
| Feature ID | CEP-002 |
| Status | 아이디어 |
| Summary | <<AI>> 직전에 실행된 프로퍼티 마이그레이션 작업을 취소하고, 영향을 받은 스키마와 값을 이전 상태로 되돌린다. |
| Related Region | file_manager_window.inspector_pane.inspector_mode_property |
| Menu | <<AI>> Edit |
| Shortcut | - |

## Preconditions

- <<AI>> 직전에 실행된 프로퍼티 마이그레이션 작업이 존재하는 상태
- <<AI>> 해당 마이그레이션 작업의 롤백 데이터(스냅샷 또는 변경 로그)가 보존된 상태
- <<AI>> 롤백을 실행할 권한을 보유한 상태
## Edge Cases

- <<AI>> 마이그레이션 이후 동일 대상에 추가 변경이 발생해 롤백 충돌이 생기는 경우
- <<AI>> 롤백 데이터가 부분적으로 손상되거나 누락된 경우
- <<AI>> 롤백 대상이 너무 커 실행 시간이 길어지는 경우

## Acceptance Criteria

- [ ] <<AI>> 직전 마이그레이션 작업이 존재하는 상태일 때, 사용자가 롤백을 실행하고 확인하면, 해당 작업으로 변경된 스키마와 값을 이전 상태로 복원함.
- [ ] <<AI>> 롤백이 불가능한 상태일 때, 사용자가 롤백을 실행하면, 실행을 차단하고 불가 사유를 표시함.
- [ ] <<AI>> 롤백이 완료된 상태일 때, 사용자가 엔트리·스키마 목록을 조회하면, 롤백 이전과 동일한 스키마/값 상태를 일관되게 표시함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `188`
