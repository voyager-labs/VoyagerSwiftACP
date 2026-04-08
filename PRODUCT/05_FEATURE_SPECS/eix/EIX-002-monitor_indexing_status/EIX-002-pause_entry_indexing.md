# Pause Entry Indexing

## Metadata

| Field            | Value                                                                                             |
| ---------------- | ------------------------------------------------------------------------------------------------- |
| Interaction ID   | EIX-002-pause_entry_indexing                                                                      |
| Interaction Type | command                                                                                           |
| Feature          | Monitor Indexing Status                                                                           |
| Category Key     | EIX                                                                                               |
| Feature ID       | EIX-002                                                                                           |
| Status           | 준비 완료                                                                                         |
| Summary          | 백그라운드 엔트리 인덱싱 작업을 일시 중지하고, 이후 재개할 수 있도록 현재 인덱싱 대기 상태를 유지 |
| Related Region   | file_manager_window.sidebar.sidebar_footer                                                        |
| Menu             | -                                                                                                 |
| Shortcut         | -                                                                                                 |

## Preconditions

- 엔트리 인데싱이 실행 중인 상태
- 엔트리 인덱싱이 일시 중지 상태가 아닌 상태

## Edge Cases

- 일시 중지 요청 시점에 인덱싱이 이미 완료·실패로 전환된 경우
- 일시 중지 상태에서 파일 시스템 변경이 발생하는 경우

## Acceptance Criteria

- [ ] 엔트리 인덱싱이 계속 진행 중일 때, 사용자가 해당 인터랙션을 호출하면, 시스템이 엔트리 인덱싱을
      일시 중지 상태로 전환하고 인덱싱 큐의 처리를 중단함
- [ ] 엔트리 인덱싱이 일시 중지 상태로 전환될 때, 시스템이 상태 전환을 반영하면, 인덱싱 상태 요약
      표시를 일시 중지 상태로 갱신함
- [ ] 일시 중지 요청 시점에 인덱싱이 이미 완료·실패로 전환된 경우일 때, 시스템이 일시 중지를
      처리하면, 일시 중지 상태로 전환하지 않고 전환된 상태를 유지함
- [ ] 일시 중지 상태에서 파일 시스템 변경이 발생하는 경우일 때, 시스템이 이벤트를 처리하면, 변경
      이벤트를 기준으로 즉시 인덱싱을 수행하지 않고 재개 시점에 델타 스캔으로 변경분을 수집해 인덱싱
      큐에 반영함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `74`
