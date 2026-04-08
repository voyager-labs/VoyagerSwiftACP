# Bridge External File System Changes to App

## Metadata

| Field            | Value                                                                                                                                              |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| Interaction ID   | EIX-001-bridge_external_file_system_changes_to_app                                                                                                 |
| Interaction Type | background                                                                                                                                         |
| Feature          | Index Entries                                                                                                                                      |
| Category Key     | EIX                                                                                                                                                |
| Feature ID       | EIX-001                                                                                                                                            |
| Status           | 기획 완료                                                                                                                                          |
| Summary          | Helper가 감지한 외부 파일시스템 변경 경로를 메인 앱 런타임으로 전달해 app-wide invalidation 갱신과 route별 reload·stale 반응을 트리거할 수 있게 함 |
| Related Region   | -                                                                                                                                                  |
| Menu             | -                                                                                                                                                  |
| Shortcut         | -                                                                                                                                                  |

## Preconditions

- VoyagerHelper가 외부 파일시스템 변경 경로 이벤트를 생성할 수 있는 상태
- 메인 앱이 helper-originated 변경 신호를 수신할 수 있는 브리지 경로를 가진 상태
- 변경 이벤트를 app-wide invalidation 갱신과 route별 반응으로 소비할 수 있는 상태

## Edge Cases

- 메인 앱이 꺼져 있는 동안 누적된 변경 이벤트를 coalesced replay payload로 다시 전달해야 하는 경우
- helper와 메인 앱 버전 또는 계약이 일치하지 않아 payload를 바로 소비할 수 없는 경우
- 동일 경로의 변경 이벤트가 중복 전달되는 경우
- 앱이 변경 신호를 수신했지만 해당 시점에 열린 route가 없거나, route별 반응 조건이 충족되지 않는
  경우

## Acceptance Criteria

- [ ] VoyagerHelper가 외부 파일시스템 변경을 감지해 이벤트를 생성하면, 메인 앱은 앱 생명주기
      수준에서 그 변경 신호를 수신할 수 있음
- [ ] 메인 앱은 수신한 변경 신호를 소비할 때, 닫힌 collection invalidation record를 앱 전역에서 먼저
      갱신하고 이후 route별 reload 또는 stale 반응으로 내려보낼 수 있음
- [ ] 메인 앱이 종료된 동안 누적된 변경이 있다면, 시스템은 이를 coalesced replay payload로 다시
      전달하고 앱이 처리 완료를 확인한 뒤 관련 backlog를 정리함
- [ ] 동일 경로 또는 동일 의미의 변경 이벤트가 중복 전달되면, 시스템은 route 반응이 과도하게
      반복되지 않도록 중복 소비를 억제하거나 병합함
- [ ] helper와 앱 사이 계약 문제로 현재 이벤트를 바로 소비하지 못할 수 있으며, helper store에 이미
      유지된 replay payload만 이후 재소비 가능함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `74`
