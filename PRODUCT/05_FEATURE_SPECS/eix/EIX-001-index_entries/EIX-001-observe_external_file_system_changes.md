# Observe External File System Changes

## Metadata

| Field            | Value                                                                                                                           |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Interaction ID   | EIX-001-observe_external_file_system_changes                                                                                    |
| Interaction Type | background                                                                                                                      |
| Feature          | Index Entries                                                                                                                   |
| Category Key     | EIX                                                                                                                             |
| Feature ID       | EIX-001                                                                                                                         |
| Status           | 기획 완료                                                                                                                       |
| Summary          | VoyagerHelper가 등록된 broad watch roots 범위에서 메인 앱과 분리된 상태로 외부 파일시스템 변경을 감지해 변경 경로 이벤트를 생성 |
| Related Region   | -                                                                                                                               |
| Menu             | -                                                                                                                               |
| Shortcut         | -                                                                                                                               |

## Preconditions

- 외부 파일시스템 감시 책임이 VoyagerHelper에 할당된 상태
- helper folder access가 허용된 broad watch roots가 helper에 등록된 상태
- 감시를 시작하는 데 필요한 권한 또는 접근성이 확보된 상태

## Edge Cases

- helper가 재시작되거나 중복 실행되어 감시 세션을 다시 정리해야 하는 경우
- 메인 앱이 종료된 상태에서 helper가 계속 살아 있는 동안 외부 변경이 연속으로 발생하는 경우
- 권한이 없거나 감시 대상 스토리지가 일시적으로 분리되는 경우
- 짧은 시간 안에 동일 경로 또는 인접 경로에서 대량 변경 이벤트가 발생하는 경우

## Acceptance Criteria

- [ ] 외부 파일시스템 감시가 활성화된 상태일 때, VoyagerHelper는 helper가 살아 있는 동안 등록된
      broad watch roots 범위의 외부 변경을 계속 감지함
- [ ] 시스템이 외부 변경을 감지하면, 이후 앱이 소비할 수 있는 변경 경로 이벤트를 생성하고 helper
      replay store에 coalesced payload로 유지함
- [ ] helper가 재시작되거나 중복 실행 조건이 발생하면, 시스템은 감시 책임을 하나의 유효한 helper
      인스턴스로 정리함
- [ ] 권한 또는 스토리지 접근 문제로 감시를 계속할 수 없다면, 해당 broad watch roots의 감시는 중단될
      수 있으며 이후 watch roots 재등록을 통해 다시 활성화될 수 있음
- [ ] 동일 경로 또는 인접 경로에서 변경 이벤트가 짧은 시간에 몰리면, 시스템은 중복 이벤트를 그대로
      누적하지 않고 후속 소비가 가능한 형태로 정규화하거나 병합함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `73`
