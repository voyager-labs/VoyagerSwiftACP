# Build Organize Commands from Request

## Metadata

| Field            | Value                                                                                                                    |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Interaction ID   | CDA-004-build_organize_commands_from_request                                                                             |
| Interaction Type | background                                                                                                               |
| Feature          | Handle Organize Intent                                                                                                   |
| Category Key     | CDA                                                                                                                      |
| Feature ID       | CDA-004                                                                                                                  |
| Status           | 기획 완료                                                                                                                |
| Summary          | Organize Intent Chunk 내용과 이전 컨텍스트를 기반으로 실제 실행될 스코프의 Working Set을 생성하고, 정리 명령 목록을 생성 |
| Related Region   | -                                                                                                                        |
| Menu             | -                                                                                                                        |
| Shortcut         | -                                                                                                                        |

## Preconditions

- Organize Intent로 분류된 Chunk가 하나 이상 존재하는 상태
- 현재 사용자에게 대상 Entry에 대한 쓰기 권한이 있음

## Edge Cases

- <<AI>> 대상 entry가 하나도 선택되지 않은 경우
- <<AI>> 일부 entry에 대한 쓰기 권한이 부족한 경우
- <<AI>> 서로 충돌하는 명령이나 위험도가 높은 명령이 동시에 생성되는 경우

## Acceptance Criteria

- [ ] <<AI>> User Request가 Organize Intent로 분류되고 대상 entry가 식별 가능한 상태일 때, 시스템이
      Build Organize Commands from Request 인터랙션을 실행하면, 각 entry에 대해 수행할 정리 명령
      목록이 생성됨.
- [ ] <<AI>> 대상 entry 일부에 쓰기 권한이 없는 상태일 때, 시스템이 Build Organize Commands from
      Request 인터랙션을 실행하면, 권한이 있는 entry에 대한 명령만 생성되고 권한이 없는 entry는 오류
      정보와 함께 제외됨.
- [ ] <<AI>> 생성된 명령 중 서로 충돌하거나 위험도가 높은 명령이 포함된 상태일 때, 시스템이 Build
      Organize Commands from Request 인터랙션을 실행하면, 해당 명령에 별도 플래그가 설정되어 프리뷰
      단계에서 강조 표시됨.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `163`
