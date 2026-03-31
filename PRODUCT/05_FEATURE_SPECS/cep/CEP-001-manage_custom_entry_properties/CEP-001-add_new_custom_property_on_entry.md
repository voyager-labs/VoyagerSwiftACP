# Add New Custom Property on Entry

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CEP-001-add_new_custom_property_on_entry |
| Interaction Type | command |
| Feature | Manage Custom Entry Properties |
| Category Key | CEP |
| Feature ID | CEP-001 |
| Status | 드래프트 |
| Summary | <<AI>> 선택한 엔트리에 새 사용자 정의 프로퍼티를 추가하고 초기 값을 설정한다. 필요 시 워크스페이스 차원의 프로퍼티 스키마도 함께 생성한다. |
| Related Region | file_manager_window.inspector_pane.inspector_mode_property |
| Menu | <<AI>> Edit |
| Shortcut | - |

## Preconditions

- <<AI>> 하나 이상의 엔트리가 선택된 상태- 인스펙터 패인이 프로퍼티 모드이거나 커스텀 프로퍼티 편집 UI에 접근 가능한 상태
- <<AI>> 선택된 엔트리(들)에 사용자 정의 프로퍼티를 기록할 수 있는 권한이 확보된 상태
## Edge Cases

- <<AI>> 입력한 프로퍼티 키가 워크스페이스에 이미 존재하는 경우
- <<AI>> 입력한 프로퍼티 키가 비어있거나 허용되지 않은 문자·형식을 포함하는 경우
- <<AI>> 선택한 프로퍼티 타입과 초기 값이 호환되지 않는 경우
- <<AI>> 복수 엔트리가 선택된 상태에서 일부 엔트리에만 적용이 가능한 경우
- <<AI>> 저장 과정에서 워크스페이스 스키마 생성 또는 값 저장이 실패하는 경우
- <<AI>> 인젝션이 의심되는 입력이 포함된 경우

## Acceptance Criteria

- [ ] <<AI>> 하나 이상의 엔트리가 선택된 상태일 때, 사용자가 새 프로퍼티 키·타입·초기 값을 입력하고 저장하면, 선택된 엔트리(들)에 커.스텀 프로퍼티를 추가하고 값을 저장함.
- [ ] <<AI>> 동일 키의 프로퍼티 스키마가 워크스페이스에 없는 상태일 때, 사용자가 저장하면, 워크스페이스 차원의 프로퍼티 스키마를 생성하고 엔트리 프로퍼티가 해당 스키마를 참조하게 함.
- [ ] <<AI>> 키 또는 초기 값 입력이 유효하지 않은 상태일 때, 사용자가 저장하면, 저장을 차단하고 유효성 오류를 표시함.
- [ ] <<AI>> 복수 엔트리 중 일부에만 저장이 성공한 상태일 때, 시스템이 결과를 표시하면, 성공·실패 대상을 구분해 표시하고 실패 사유를 제공함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `174`
