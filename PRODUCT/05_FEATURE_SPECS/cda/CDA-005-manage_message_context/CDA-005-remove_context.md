# Remove Context

## Metadata

| Field            | Value                                                  |
| ---------------- | ------------------------------------------------------ |
| Interaction ID   | CDA-005-remove_context                                 |
| Interaction Type | command                                                |
| Feature          | Manage Message Context                                 |
| Category Key     | CDA                                                    |
| Feature ID       | CDA-005                                                |
| Status           | 기획 완료                                              |
| Summary          | 현재 챗 필드에 추가된 해당 컨텍스트를 제거             |
| Related Region   | file_manager_window.inspector_pane.inspector_mode_chat |
| Menu             | -                                                      |
| Shortcut         | ⌫                                                      |

## Preconditions

- <<AI>> 현재 챗 필드에 하나 이상의 컨텍스트 칩이 추가된 상태
- <<AI>> 사용자가 제거 대상으로 삼을 컨텍스트 칩을 식별하거나 선택할 수 있는 상태

## Edge Cases

- <<AI>> 현재 메시지에 단 하나의 컨텍스트만 존재하는 상태에서 이를 제거하는 경우
- <<AI>> 동일 컨텍스트에 대해 제거 인터랙션이 연속으로 호출되는 경우
- <<AI>> 컨텍스트 제거 직후 사용자가 Undo 등 복구 동작을 수행하는 경우

## Acceptance Criteria

- [ ] <<AI>> 현재 메시지에 하나 이상의 컨텍스트가 존재하는 상태에서 사용자가 특정 컨텍스트 칩에 대해
      Remove Context 인터랙션을 호출하면, 해당 컨텍스트가 메시지의 컨텍스트 목록에서 제거되고 칩이
      즉시 사라짐.
- [ ] <<AI>> 현재 메시지에 하나의 컨텍스트만 존재하는 상태에서 사용자가 Remove Context 인터랙션을
      호출하면, 해당 컨텍스트가 제거되어 메시지는 명시적 컨텍스트 없이 암묵적 컨텍스트만 사용하는
      상태가 됨.
- [ ] <<AI>> 이미 제거된 컨텍스트에 대해 Remove Context 인터랙션이 다시 호출된 상태일 때, 추가적인
      상태 변화는 발생하지 않고 기존 메시지 컨텍스트 상태가 유지됨.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `172`
