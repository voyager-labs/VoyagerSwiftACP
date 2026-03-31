# Delete Custom Property

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CEP-001-delete_custom_property |
| Interaction Type | input |
| Feature | Manage Custom Entry Properties |
| Category Key | CEP |
| Feature ID | CEP-001 |
| Status | 드래프트 |
| Summary | <<AI>> 선택한 엔트리에서 커스텀 프로퍼티를 제거하고, 필요 시 워크스페이스 차원에서 프로퍼티 스키마를 비활성화하거나 삭제하는 옵션을 제공한다. |
| Related Region | file_manager_window.inspector_pane.inspector_mode_property |
| Menu | <<AI>> Edit |
| Shortcut | - |

## Preconditions

- <<AI>> 하나 이상의 엔트리가 선택된 상태- 제거할 커스텀 프로퍼티가 선택된 상태
- <<AI>> 선택된 엔트리(들)에 해당 커스텀 프로퍼티가 존재하는 상태
- <<AI>> 선택된 엔트리(들)에서 사용자 정의 프로퍼티를 수정·삭제할 권한이 확보된 상태
## Edge Cases

- <<AI>> 선택된 엔트리 중 일부에만 해당 프로퍼티가 존재하는 경우
- <<AI>> 대상 프로퍼티 스키마가 필수(Required)로 지정되어 제거가 제한되는 경우
- <<AI>> 대상 스키마가 다른 엔트리·규칙·컬렉션 정의에서 사용 중이라 스키마 삭제가 위험한 경우
- <<AI>> 제거 작업 중 일부 엔트리에서만 실패하는 경우

## Acceptance Criteria

- [ ] <<AI>> 제거할 커스텀 프로퍼티가 선택된 상태일 때, 사용자가 제거를 실행하면, 선택된 엔트리(들)에서 해당 프로퍼티 값을 제거하고 UI를 갱신함.
- [ ] <<AI>> 스키마 비활성화 또는 삭제 옵션을 선택한 상태일 때, 사용자가 확인하고 실행하면, 워크스페이스 스키마를 비활성화하거나 삭제하고 이후 신규 추가 UI에서 선택되지 않게 함.
- [ ] <<AI>> 대상 스키마가 다른 참조에 의해 사용 중인 상태일 때, 사용자가 스키마 삭제를 실행하면, 삭제를 차단하고 사용 현황 및 대안(비활성화 등)을 표시함.
- [ ] <<AI>> 제거 작업이 부분 실패한 상태일 때, 시스템이 결과를 표시하면, 성공·실패 대상을 구분해 표시하고 실패 사유를 제공함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `177`
