# Index System Property

## Metadata

| Field            | Value                                                                            |
| ---------------- | -------------------------------------------------------------------------------- |
| Interaction ID   | EIX-004-index_system_property                                                    |
| Interaction Type | background                                                                       |
| Feature          | Index System Properties                                                          |
| Category Key     | EIX                                                                              |
| Feature ID       | EIX-004                                                                          |
| Status           | 취소                                                                             |
| Summary          | 시스템 프로퍼티 조회는 별도 인덱싱 대신 macOS Spotlight 메타데이터 인덱스를 사용 |
| Related Region   | -                                                                                |
| Menu             | -                                                                                |
| Shortcut         | -                                                                                |

## Preconditions

- <<AI>> 대상 Entry가 인덱싱 대상으로 분류된 상태
- <<AI>> 대상 Entry에 대한 파일 접근 권한이 확보된 상태

## Edge Cases

- <<AI>> 수집 중 대상 Entry가 이동·이름 변경되어 경로가 변하는 경우
- <<AI>> 대상 Entry가 심볼릭 링크 또는 별칭 등으로 실제 경로 해석이 필요한 경우
- <<AI>> 권한 또는 스토리지 연결 문제로 메타데이터 조회가 실패하는 경우

## Acceptance Criteria

- [ ] <<AI>> 대상 Entry가 인덱싱 대상인 상태일 때, 시스템이 수집을 수행하면,
      경로·이름·확장자·용량·생성/수정 시각 등 시스템 프로퍼티 인덱스를 갱신함.
- [ ] <<AI>> 대상 Entry의 시스템 프로퍼티가 변경된 상태일 때, 시스템이 증분 갱신을 수행하면, 변경된
      값을 인덱스에 반영함.
- [ ] <<AI>> 수집이 실패한 상태일 때, 시스템이 오류를 기록하면, 실패 원인을 저장하고 재시도 가능
      상태로 유지함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `85`
