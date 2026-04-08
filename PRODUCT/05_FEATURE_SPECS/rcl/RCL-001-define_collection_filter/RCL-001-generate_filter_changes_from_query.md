# Generate Filter Changes from Query

## Metadata

| Field            | Value                                                                    |
| ---------------- | ------------------------------------------------------------------------ |
| Interaction ID   | RCL-001-generate_filter_changes_from_query                               |
| Interaction Type | background                                                               |
| Feature          | Define Collection Filter                                                 |
| Category Key     | RCL                                                                      |
| Feature ID       | RCL-001                                                                  |
| Status           | 배포 완료                                                                |
| Summary          | 제출된 쿼리를 해석해 현재 필터에 반영할 구조화 조건 변경안을 산출해 반환 |
| Related Region   | -                                                                        |
| Menu             | -                                                                        |
| Shortcut         | -                                                                        |

## Preconditions

- Submit Collection Filter Query가 발생한 상태

## Edge Cases

- 아무 조건이 생성되지 않고 반환되는 경우
- 생성이 실패/오류로 종료되는 경우

## Acceptance Criteria

- [ ] Submit Collection Filter Query가 발생한 상태일 때, 시스템이 제출된 쿼리를 처리하면, 필터
      변경안을 생성해 결과로 반환함
- [ ] 시스템이 쿼리를 처리했을 때 생성된 조건이 없다면, 빈 변경안을 반환함
- [ ] 시스템이 쿼리를 처리했을 때 실패/오류로 종료되면, 실패 상태와 오류 정보를 반환함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `105`
