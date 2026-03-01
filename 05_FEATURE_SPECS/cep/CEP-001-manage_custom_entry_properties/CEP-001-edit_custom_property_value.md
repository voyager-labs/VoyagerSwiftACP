# Edit Custom Property Value

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CEP-001-edit_custom_property_value |
| Interaction Type | input |
| Feature | Manage Custom Entry Properties |
| Category Key | CEP |
| Feature ID | CEP-001 |
| Status | 드래프트 |
| Summary | <<AI>> 선택한 엔트리에서 사용 중인 커스텀 프로퍼티의 라벨, 설명, 표시 옵션 등 정의 정보를 수정하고, 동일 프로퍼티를 사용하는 다른 엔트리에도 반영한다. |
| Related Region | file_manager_window.inspector_pane.inspector_mode_property |
| Menu | - |
| Shortcut | - |

## Preconditions

- <<AI>> 편집할 커스텀 프로퍼티가 선택된 상태
- <<AI>> 대상 프로퍼티가 워크스페이스 스키마로 등록되어 있는 상태
- <<AI>> 프로퍼티 스키마를 편집할 권한을 보유한 상태
## Edge Cases

- <<AI>> 라벨·설명이 비어있거나 길이 제한을 초과하는 경우
- <<AI>> 표시 옵션이 프로퍼티 타입 또는 현재 UI와 호환되지 않는 경우
- <<AI>> 동일 스키마에 대한 동시 편집으로 충돌이 발생하는 경우
- <<AI>> 인젝션이 의심되는 입력이 포함된 경우

## Acceptance Criteria

- [ ] <<AI>> 프로퍼티 편집 UI가 열린 상태일 때, 사용자가 유효한 정의 정보(라벨, 설명, 표시 옵션)를 저장하면, 워크스페이스 전역 스키마를 업데이트하고 동일 스키마를 사용하는 모든 엔트리의 표시를 반영함.
- [ ] <<AI>> 입력이 유효하지 않은 상태일 때, 사용자가 저장하면, 저장을 차단하고 유효성 오류를 표시함.
- [ ] <<AI>> 동시 편집 충돌이 감지된 상태일 때, 사용자가 저장하면, 저장을 차단하고 최신 버전 기준의 재시도 또는 병합 안내를 표시함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `176`
