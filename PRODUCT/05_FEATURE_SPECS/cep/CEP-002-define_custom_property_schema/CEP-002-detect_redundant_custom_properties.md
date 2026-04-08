# Detect Redundant Custom Properties

## Metadata

| Field            | Value                                                                                                            |
| ---------------- | ---------------------------------------------------------------------------------------------------------------- |
| Interaction ID   | CEP-002-detect_redundant_custom_properties                                                                       |
| Interaction Type | background                                                                                                       |
| Feature          | Define Custom Property Schema                                                                                    |
| Category Key     | CEP                                                                                                              |
| Feature ID       | CEP-002                                                                                                          |
| Status           | 아이디어                                                                                                         |
| Summary          | <<AI>> 이름·타입·사용처가 유사한 중복·유사 사용자 프로퍼티 스키마 후보를 자동으로 탐지해 정리 대상으로 제안한다. |
| Related Region   | -                                                                                                                |
| Menu             | -                                                                                                                |
| Shortcut         | -                                                                                                                |

## Preconditions

- <<AI>> 워크스페이스에 2개 이상의 사용자 프로퍼티 스키마가 존재하는 상태
- <<AI>> 중복 탐지를 위한 사용 현황 또는 스키마 메타데이터를 조회할 수 있는 상태
- <<AI>> 중복 탐지 작업이 실행 중이지 않은 상태

## Edge Cases

- <<AI>> 이름·타입은 유사하지만 실제 의미가 달라 오탐이 발생하는 경우
- <<AI>> 유사도 기준을 만족하는 후보가 존재하지 않는 경우
- <<AI>> 탐지 중 스키마가 변경되어 결과가 일시적으로 불일치하는 경우

## Acceptance Criteria

- [ ] <<AI>> 중복 탐지 작업이 실행된 상태일 때, 시스템이 탐지를 완료하면, 유사 스키마 후보 그룹을
      산출해 저장함.
- [ ] <<AI>> 사용자가 중복 후보를 조회하는 상태일 때, 시스템이 후보 그룹을 로드하면, 후보 그룹과
      근거(유사 키·라벨, 타입, 사용처 요약)를 함께 표시함.
- [ ] <<AI>> 후보가 없는 상태일 때, 화면이 표시되면, 빈 결과 상태를 표시함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `184`
