# Migrate Custom Property Values

## Metadata

| Field            | Value                                                                                                              |
| ---------------- | ------------------------------------------------------------------------------------------------------------------ |
| Interaction ID   | CEP-002-migrate_custom_property_values                                                                             |
| Interaction Type | command                                                                                                            |
| Feature          | Define Custom Property Schema                                                                                      |
| Category Key     | CEP                                                                                                                |
| Feature ID       | CEP-002                                                                                                            |
| Status           | 아이디어                                                                                                           |
| Summary          | <<AI>> 병합·변경된 스키마에 맞춰 기존 엔트리의 사용자 프로퍼티 값을 자동으로 이동·정규화하는 배치 작업을 실행한다. |
| Related Region   | file_manager_window.inspector_pane.inspector_mode_property                                                         |
| Menu             | <<AI>> Edit                                                                                                        |
| Shortcut         | -                                                                                                                  |

## Preconditions

- <<AI>> 마이그레이션 대상 스키마 변경(병합 또는 타입/제약 변경)이 존재하는 상태
- <<AI>> 마이그레이션 대상 엔트리 집합이 식별된 상태
- <<AI>> 마이그레이션 작업이 실행 중이지 않은 상태

## Edge Cases

- <<AI>> 일부 엔트리에서 값 변환이 불가능해 타입 캐스팅 오류가 발생하는 경우
- <<AI>> 일부 스토리지·엔트리에 접근할 수 없어 부분 실행만 가능한 경우
- <<AI>> 작업 중 앱이 종료되거나 시스템이 재시작되는 경우
- <<AI>> 마이그레이션 중 동일 엔트리 값이 동시 편집되어 충돌이 발생하는 경우

## Acceptance Criteria

- [ ] <<AI>> 마이그레이션이 실행 가능한 상태일 때, 사용자가 실행하면, 배치 작업을 시작하고 진행
      상태(대상 수, 진행률, 성공/실패)를 기록함.
- [ ] <<AI>> 마이그레이션이 완료된 상태일 때, 시스템이 결과를 반영하면, 영향을 받은 엔트리의 값을 새
      스키마 기준으로 이동·정규화하고 검색·필터 결과에 반영함.
- [ ] <<AI>> 일부 값이 변환 불가능한 상태일 때, 시스템이 마이그레이션을 수행하면, 해당 엔트리를
      실패로 표시하고 오류 이유 및 수동 처리 옵션을 제공함.
- [ ] <<AI>> 마이그레이션이 중단된 상태일 때, 사용자가 상태를 조회하면, 재시도 및 롤백 옵션을
      표시함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `186`
