# Create Computed Property

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CEP-003-create_computed_property |
| Interaction Type | command |
| Feature | Computed Properties |
| Category Key | CEP |
| Feature ID | CEP-003 |
| Status | 아이디어 |
| Summary | <<AI>> 다른 프로퍼티나 시스템 메타데이터를 조합해 자동 계산되는 새 Computed Property를 정의한다. |
| Related Region | file_manager_window.inspector_pane.inspector_mode_property |
| Menu | <<AI>> Edit |
| Shortcut | - |

## Preconditions

- <<AI>> Computed Property를 정의할 수 있는 화면이 열린 상태
- <<AI>> 참조 가능한 기본 프로퍼티 스키마가 하나 이상 존재하는 상태
- <<AI>> Computed Property를 생성할 권한을 보유한 상태
## Edge Cases

- <<AI>> 입력한 키가 기존 프로퍼티(일반/Computed) 키와 중복되는 경우
- <<AI>> 수식 문법이 유효하지 않거나 평가할 수 없는 경우
- <<AI>> 참조 프로퍼티 타입이 맞지 않아 계산 결과 타입이 결정되지 않는 경우
- <<AI>> 순환 참조가 발생하는 경우

## Acceptance Criteria

- [ ] <<AI>> 생성 화면이 열린 상태일 때, 사용자가 유효한 키·라벨·수식을 입력하고 저장하면, 새 Computed Property 스키마를 생성하고 엔트리에서 계산된 값을 표시함.
- [ ] <<AI>> 수식이 유효하지 않거나 순환 참조인 상태일 때, 사용자가 저장하면, 저장을 차단하고 오류를 표시함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `189`
