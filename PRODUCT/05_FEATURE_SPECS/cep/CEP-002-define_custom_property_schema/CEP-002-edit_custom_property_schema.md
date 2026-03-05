# Edit Custom Property Schema

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CEP-002-edit_custom_property_schema |
| Interaction Type | input |
| Feature | Define Custom Property Schema |
| Category Key | CEP |
| Feature ID | CEP-002 |
| Status | 아이디어 |
| Summary | <<AI>> 기존 사용자 프로퍼티 스키마의 이름, 설명, 타입, 표시 옵션 등을 수정해 워크스페이스 전역 정의를 업데이트한다. |
| Related Region | file_manager_window.inspector_pane.inspector_mode_property |
| Menu | - |
| Shortcut | - |

## Preconditions

- <<AI>> 편집할 프로퍼티 스키마가 선택된 상태
- <<AI>> 대상 스키마가 삭제되지 않고 접근 가능한 상태
- <<AI>> 프로퍼티 스키마를 편집할 권한을 보유한 상태
## Edge Cases

- <<AI>> 스키마 타입 변경이 기존 엔트리 값과 호환되지 않는 경우- 옵션 값(enum) 변경으로 기존 값이 제약을 위반하는 경우
- <<AI>> 동일 스키마에 대한 동시 편집으로 충돌이 발생하는 경우
- <<AI>> 스키마 변경으로 컬렉션 정의·규칙·Computed Property가 무효화되는 경우
- <<AI>> 인젝션이 의심되는 입력이 포함된 경우

## Acceptance Criteria

- [ ] <<AI>> 스키마 편집 화면이 열린 상태일 때, 사용자가 유효한 변경(이름, 설명, 타입, 표시 옵션)을 저장하면, 워크스페이스 전역 스키마 정의를 업데이트하고 관련 UI/검증 규칙을 즉시 반영함.
- [ ] <<AI>> 타입 또는 옵션 변경이 기존 값과 호환되지 않은 상태일 때, 사용자가 저장하면, 저장을 차단하거나 값 마이그레이션 플로우로 안내함.
- [ ] <<AI>> 입력이 유효하지 않은 상태일 때, 사용자가 저장하면, 저장을 차단하고 유효성 오류를 표시함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `180`
