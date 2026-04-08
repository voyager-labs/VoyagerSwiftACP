# Request Collection Results Refresh

## Metadata

| Field            | Value                                                                                                                                           |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Interaction ID   | RCL-003-request_collection_results_refresh                                                                                                      |
| Interaction Type | command                                                                                                                                         |
| Feature          | Retrieve Entries with Filters                                                                                                                   |
| Category Key     | RCL                                                                                                                                             |
| Feature ID       | RCL-003                                                                                                                                         |
| Status           | 아이디어                                                                                                                                        |
| Summary          | stale 상태를 알리는 affordance가 제공될 경우, 사용자가 기존 RCL-003-refresh_collection_results를 직접 호출할 수 있도록 하는 command interaction |
| Related Region   | file_manager_window.content_pane.content_header                                                                                                 |
| Menu             | -                                                                                                                                               |
| Shortcut         | -                                                                                                                                               |

## Preconditions

- 현재 콜렉션 결과가 stale 상태로 판단된 상태
- 사용자가 stale 상태를 인지할 수 있는 affordance가 제공되는 상태

## Edge Cases

- 현재 브랜치에서는 stale badge UI와 manual refresh affordance UI가 아직 미구현인 경우
- stale 상태가 해제되기 직전에 사용자가 refresh를 요청하는 경우
- 자동 refresh가 아니라 명시적 사용자 요청만 허용해야 하는 경우

## Acceptance Criteria

- [ ] stale 상태를 알리는 UI affordance가 제공될 때, 사용자가 해당 affordance에서 직접 결과
      refresh를 요청할 수 있어야 함
- [ ] 시스템은 이 interaction을 자동 refresh와 구분되는 명시적 사용자 command로 취급함
- [ ] refresh 요청은 현재 stale 상태의 collection 결과를 최신 결과로 갱신하기 위해 기존
      `RCL-003-refresh_collection_results` 실행 경로를 트리거하는 명시적 시도로 연결됨
- [ ] 이 interaction은 Task 9 범위의 planned affordance이며, 현재 브랜치에 이미 구현된 동작으로
      간주하지 않음

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `146`
