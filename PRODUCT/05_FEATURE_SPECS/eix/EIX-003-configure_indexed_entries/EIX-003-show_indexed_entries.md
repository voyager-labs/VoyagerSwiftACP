# Show Indexed Entries

## Metadata

| Field            | Value                                      |
| ---------------- | ------------------------------------------ |
| Interaction ID   | EIX-003-show_indexed_entries               |
| Interaction Type | display                                    |
| Feature          | Configure Indexed Entries                  |
| Category Key     | EIX                                        |
| Feature ID       | EIX-003                                    |
| Status           | 준비 완료                                  |
| Summary          | 인덱싱이 완료된 엔트리 목록을 표시         |
| Related Region   | settings_window.settings_body.tab_indexing |
| Menu             | -                                          |
| Shortcut         | -                                          |

## Preconditions

- <<TEMP>>
- 인덱싱 설정 화면이 표시된 상태

## Edge Cases

- 인덱싱 대상이 비어 있는 경우
- 인덱싱 상태 갱신 중이라 트리 목록이 일시적으로 최신이 아닌 경우

## Acceptance Criteria

- [ ] 인덱싱 설정 화면이 표시된 상태일 때, 시스템이 인덱싱 완료 엔트리 목록을 로드하면, 인덱싱이
      완료된 엔트리를 계층 구조의 리스트로 표시함
- [ ] 인덱싱이 완료된 엔트리가 없는 경우일 때, 시스템이 트리 리스트를 표시하면, 빈 상태를 표시함
- [ ] 인덱싱이 진행 중인 상태일 때, 시스템이 인덱싱 완료 상태를 갱신하면, 트리 리스트에 새로 완료된
      엔트리를 반영해 목록을 갱신함
- [ ] 트리 리스트가 표시된 상태일 때, 사용자가 경로 노드를 확장·접기하면, 시스템이 해당 하위 노드를
      표시하거나 숨김 처리함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `78`
