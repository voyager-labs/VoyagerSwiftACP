# Build Collection Filter Draft from Request

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CDA-003-build_collection_filter_draft_from_request |
| Interaction Type | background |
| Feature | Handle Retrieve Intent |
| Category Key | CDA |
| Feature ID | CDA-003 |
| Status | 기획 완료 |
| Summary | Retrieve Intent Chunk와 현재 컨텍스트를 기반으로 콜렉션 필터 초안을 생성하고 초안 상태(완전/불완전/충돌)를 기록 |
| Related Region | - |
| Menu | - |
| Shortcut | - |

## Preconditions

- Retrieve Intent로 분류된 Chunk가 하나 이상 존재하는 상태
## Edge Cases

- <<AI>> User Request에 검색 범위나 조건이 명시되지 않은 모호한 요청인 경우
- <<AI>> 현재 컨텍스트가 삭제되었거나 권한이 없는 위치를 가리키는 경우
- <<AI>> 예상 결과 수가 매우 많아 과도한 결과 세트가 생성될 가능성이 높은 경우

## Acceptance Criteria

- [ ] <<AI>> User Request가 Retrieve Intent로 분류된 상태일 때, 시스템이 Build Retrieval Query from Request 인터랙션을 실행하면, 검색 범위와 키워드 또는 필터가 포함된 Retrieval Query 객체가 생성됨.
- [ ] <<AI>> 현재 컨텍스트가 유효하지 않은 상태일 때, 시스템이 Build Retrieval Query from Request 인터랙션을 실행하면, Retrieval Query가 기본 검색 범위로 대체되어 안전하게 생성됨.
- [ ] <<AI>> User Request에 검색 조건이 거의 없는 상태일 때, 시스템이 Build Retrieval Query from Request 인터랙션을 실행하면, 과도한 결과를 방지하기 위한 기본 제한 조건이 포함된 Retrieval Query가 생성됨.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `152`
