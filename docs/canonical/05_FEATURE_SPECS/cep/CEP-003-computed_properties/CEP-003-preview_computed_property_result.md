# Preview Computed Property Result

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CEP-003-preview_computed_property_result |
| Interaction Type | display |
| Feature | Computed Properties |
| Category Key | CEP |
| Feature ID | CEP-003 |
| Status | 아이디어 |
| Summary | <<AI>> 샘플 엔트리 집합에 대해 Computed Property 수식이 어떻게 평가되는지 미리 계산해 결과를 보여준다. |
| Related Region | file_manager_window.inspector_pane.inspector_mode_property |
| Menu | <<AI>> View |
| Shortcut | - |

## Preconditions

- <<AI>> 미리보기할 Computed Property가 선택된 상태
- <<AI>> 샘플로 평가할 엔트리 집합이 선택되었거나 현재 목록 컨텍스트가 존재하는 상태
## Edge Cases

- <<AI>> 샘플 엔트리에서 참조 프로퍼티 값이 누락되어 평가할 수 없는 경우
- <<AI>> 샘플 엔트리 수가 많아 평가 시간이 길어지는 경우
- <<AI>> 일부 엔트리에서만 평가 오류가 발생하는 경우

## Acceptance Criteria

- [ ] <<AI>> 사용자가 미리보기를 실행할 때, 시스템이 샘플 엔트리 집합에 대해 수식을 평가하면, 엔트리별 계산 결과를 미리보기 화면에 표시함.
- [ ] <<AI>> 일부 엔트리에서 평가가 실패한 상태일 때, 미리보기 결과가 표시되면, 성공/실패를 구분해 표시하고 실패 원인을 함께 제공함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `191`
