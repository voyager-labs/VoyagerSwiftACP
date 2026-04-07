# Mark Open Collection as Stale on External Change

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-003-mark_open_collection_as_stale_on_external_change |
| Interaction Type | background |
| Feature | Retrieve Entries with Filters |
| Category Key | RCL |
| Feature ID | RCL-003 |
| Status | 기획 완료 |
| Summary | 열려 있는 콜렉션에서 외부 변경이 발생하면 자동 refresh 없이 현재 결과를 유지한 채 stale 상태만 남겨 후속 refresh 정책을 유지 |
| Related Region | file_manager_window.content_pane.page_container.page_mode_collection |
| Menu | - |
| Shortcut | - |

## Preconditions

- 현재 Content Pane이 열린 콜렉션 페이지를 표시 중인 상태
- 외부 파일시스템 변경 신호가 현재 열린 콜렉션의 scope 아래 경로와 관련된 상태

## Edge Cases

- 외부 변경이 짧은 시간 안에 반복 발생해 stale mark 요청이 연속으로 들어오는 경우
- 현재 열린 콜렉션 scope와 무관한 경로 변경이 도착하는 경우
- 열린 콜렉션에서 stale mark 직후 사용자가 수동 refresh를 호출하는 경우
- 외부 변경이 발생했지만 현재 페이지가 이미 다른 콜렉션 또는 일반 디렉토리로 전환된 경우
- 열린 콜렉션이 이미 stale 상태인데 동일 범위 변경이 다시 도착하는 경우

## Acceptance Criteria

- [ ] 현재 열린 콜렉션의 scope 아래 관련 경로에서 외부 파일시스템 변경이 발생하면, 시스템은 자동 refresh나 자동 search를 실행하지 않고 현재 결과를 stale 상태로 전환함
- [ ] 시스템이 열린 콜렉션을 stale 상태로 표시하더라도, 현재 결과 목록은 유지되고 현재 collection session은 stale 상태로 남아 사용자가 즉시 문맥을 잃지 않음
- [ ] 동일 범위의 외부 변경이 짧은 시간 안에 반복되더라도, 시스템은 열린 콜렉션을 다시 stale 상태로 유지하며 결과 목록을 그대로 둠
- [ ] 현재 열린 콜렉션 scope와 무관한 경로 변경은 stale mark 대상으로 취급하지 않음
- [ ] 사용자가 stale 상태 이후 수동 refresh를 호출하면, 시스템은 stale-only 정책과 별개로 명시적 refresh 경로를 계속 허용함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `149`
