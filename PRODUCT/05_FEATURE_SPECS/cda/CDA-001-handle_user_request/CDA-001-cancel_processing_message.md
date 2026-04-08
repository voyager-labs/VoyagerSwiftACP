# Cancel Processing Message

## Metadata

| Field            | Value                                                                |
| ---------------- | -------------------------------------------------------------------- |
| Interaction ID   | CDA-001-cancel_processing_message                                    |
| Interaction Type | command                                                              |
| Feature          | Handle User Request                                                  |
| Category Key     | CDA                                                                  |
| Feature ID       | CDA-001                                                              |
| Status           | 기획 완료                                                            |
| Summary          | 처리 중인 User Request Message의 응답 스트리밍 및 후속 처리를 중단함 |
| Related Region   | file_manager_window.inspector_pane.inspector_mode_chat               |
| Menu             | -                                                                    |
| Shortcut         | ⌃C                                                                   |

## Preconditions

- 대상 User Request Message가 처리 중인 상태

## Edge Cases

- User Request가 거의 완료된 시점에 취소 요청이 들어오는 경우
- 네트워크 지연으로 취소 요청 반영이 늦어지는 경우
- 같은 대상 User Request Message에 대해 Cancel Processing Message 인터랙션이 연속으로 여러 번
  호출되는 경우

## Acceptance Criteria

- [ ] 대상 User Request Message가 처리 중인 상태일 때, 사용자가 해당 인터랙션을 호출하면, 해당
      Request의 응답 스트리밍과 후속 처리가 즉시 중단됨
- [ ] 대상 User Request Message가 처리 중인 상태일 때, 사용자가 해당 인터랙션을 연속으로 여러 번
      호출하면, 첫 호출에서만 취소 처리가 수행되고 이후 호출에서는 추가적인 상태 변화 없이 기존 취소
      상태가 유지됨
- [ ] 사용자가 해당 인터랙션을 호출했을 때, 대상 User Request Message가 처리 응답이 거의 완료된
      시점이거나 네트워크 지연으로 취소 요청이 늦게 도달한다면, 일부 추가 토큰이 표시될 수 있으나
      취소 요청이 반영된 이후에는 더 이상 응답이 표시되지 않고 Request가 취소 상태로 유지됨

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `146`
