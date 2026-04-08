# Refresh Collection Results

## Metadata

| Field            | Value                                                                         |
| ---------------- | ----------------------------------------------------------------------------- |
| Interaction ID   | RCL-003-refresh_collection_results                                            |
| Interaction Type | command                                                                       |
| Feature          | Retrieve Entries with Filters                                                 |
| Category Key     | RCL                                                                           |
| Feature ID       | RCL-003                                                                       |
| Status           | 배포 완료                                                                     |
| Summary          | 현재 설정된 필터를 기준으로 엔트리 검색을 수동 실행해 최신 결과 목록으로 갱신 |
| Related Region   | -                                                                             |
| Menu             | -                                                                             |
| Shortcut         | -                                                                             |

## Preconditions

- 현재 콜렉션 결과가 표시 중인 상태

## Edge Cases

- 짧은 시간에 연속 호출되는 경우
- 권한 부족이나 스토리지 연결 문제로 새로고침 실행이 실패하는 경우

## Acceptance Criteria

- [ ] 현재 콜렉션 결과가 표시 중인 상태일 때, 사용자가 해당 인터랙션을 호출하면, 현재 설정된 필터로
      검색을 수동 실행해 최신 결과 목록으로 갱신함
- [ ] 사용자가 새로고침을 짧은 시간안에 연속 호출했을 때, , 중복 실행을 제한하는 정책을 적용함
- [ ] 권한 부족이나 스토리지 연결 문제로 새로고침 실행이 실패한다면, 사용자가 새로고침을 호출할 때,
      기존 결과를 유지하고 실패 피드백을 표시함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `134`
