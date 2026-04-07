# Add Inline Context Reference

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CDA-005-add_inline_context_reference |
| Interaction Type | input |
| Feature | Manage Message Context |
| Category Key | CDA |
| Feature ID | CDA-005 |
| Status | 기획 완료 |
| Summary | 챗 필드에서 특정 트리거 문자(`@`)를 사용해 엔트리 등 컨텍스트 요소를 인라인으로 참조하여 현재 메시지의 컨텍스트로 추가 |
| Related Region | file_manager_window.inspector_pane.inspector_mode_chat |
| Menu | - |
| Shortcut | - |

## Preconditions

- <<AI>> 챗 필드가 포커스된 상태
- <<AI>> 챗 필드에서 인라인 컨텍스트 트리거 문자(예: @)를 입력하면 컨텍스트 검색/선택 UI가 표시되는 상태
- <<AI>> 검색/선택 UI가 표시할 수 있는 컨텍스트 후보(엔트리·페이지·채팅 등)가 존재하는 상태
## Edge Cases

- <<AI>> 사용자가 트리거 문자를 입력했지만 검색 결과가 비어 있는 경우
- <<AI>> 사용자가 인라인 검색 UI에서 아무 항목도 선택하지 않고 입력을 종료하는 경우
- <<AI>> 이미 메시지의 컨텍스트로 추가된 대상을 인라인에서 다시 참조하는 경우

## Acceptance Criteria

- [ ] <<AI>> 챗 필드가 포커스된 상태에서 사용자가 트리거 문자와 검색어를 입력하고 후보 목록에서 대상을 선택하면, 선택된 대상이 현재 메시지의 컨텍스트로 추가되고 인라인 텍스트에는 해당 참조가 하이라이트 또는 토큰 형태로 표시됨.
- [ ] <<AI>> 검색 결과가 비어 있는 상태에서 사용자가 인라인 컨텍스트를 선택하려고 시도하면, 컨텍스트가 추가되지 않고 검색 결과 없음 상태가 사용자에게 표시됨.
- [ ] <<AI>> 이미 컨텍스트로 추가된 대상을 인라인에서 다시 참조하는 상태에서 사용자가 해당 인터랙션을 수행하면, 인라인 참조는 추가되지만 중복 컨텍스트가 생성되지 않거나, 중복 정책에 따라 정의된 동작(예: 기존 컨텍스트와 인라인 참조 연결)이 수행됨.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `171`
