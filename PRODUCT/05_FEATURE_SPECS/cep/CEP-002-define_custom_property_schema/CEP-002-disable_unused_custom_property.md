# Disable Unused Custom Property

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CEP-002-disable_unused_custom_property |
| Interaction Type | command |
| Feature | Define Custom Property Schema |
| Category Key | CEP |
| Feature ID | CEP-002 |
| Status | 아이디어 |
| Summary | <<AI>> 사용량이 거의 없거나 더 이상 쓰지 않는 사용자 프로퍼티 스키마를 비활성화해 신규 엔트리에서 사용되지 않게 한다. |
| Related Region | file_manager_window.inspector_pane.inspector_mode_property |
| Menu | <<AI>> Edit |
| Shortcut | - |

## Preconditions

- <<AI>> 스키마 사용 현황이 계산되어 있는 상태
- <<AI>> 비활성화할 스키마 후보가 선택되었거나 시스템 추천 목록이 표시된 상태
- <<AI>> 프로퍼티 스키마를 편집할 권한을 보유한 상태
## Edge Cases

- <<AI>> 사용량은 낮지만 컬렉션 정의·규칙·Computed Property에서 참조되는 경우
- <<AI>> 사용 현황이 최신이 아니어서 실제 사용량과 불일치하는 경우

## Acceptance Criteria

- [ ] <<AI>> 사용 현황 기반 후보 스키마가 표시된 상태일 때, 사용자가 비활성화를 실행하면, 해당 스키마를 비활성 상태로 전환하고 신규 추가 UI에서 숨김 처리함.
- [ ] <<AI>> 스키마가 참조 중인 상태일 때, 사용자가 비활성화를 실행하면, 비활성화를 차단하고 참조 위치를 표시함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `187`
