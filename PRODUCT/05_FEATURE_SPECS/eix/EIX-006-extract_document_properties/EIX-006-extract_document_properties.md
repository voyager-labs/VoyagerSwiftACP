# Extract Document Properties

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EIX-006-extract_document_properties |
| Interaction Type | background |
| Feature | Extract Document Properties |
| Category Key | EIX |
| Feature ID | EIX-006 |
| Status | 드래프트 |
| Summary | 문서·프레젠테이션 계열 Entry에서 문서 타입·제목·클라이언트·프로젝트·요약 등 문서 관련 자동 프로퍼티를 추출해 Entry 프로퍼티로 저장 |
| Related Region | - |
| Menu | - |
| Shortcut | - |

## Preconditions

- <<AI>> 대상 Entry가 문서·프레젠테이션 계열 포맷으로 분류된 상태
- <<AI>> 문서 프로퍼티 추출 파이프라인이 활성화된 상태
- <<AI>> 대상 Entry의 콘텐츠를 읽을 수 있는 권한이 확보된 상태
## Edge Cases

- <<AI>> 문서가 암호화·잠금 상태이거나 권한 제한으로 열람할 수 없는 경우
- <<AI>> 문서가 손상되었거나 포맷 파서가 지원하지 않는 버전인 경우
- <<AI>> 문서에 텍스트가 거의 없거나 이미지 기반이라 입력이 부족한 경우

## Acceptance Criteria

- [ ] <<AI>> 대상 Entry가 문서 포맷인 상태일 때, 시스템이 추출을 수행하면, 문서 타입·제목·요약·키포인트 등 자동 프로퍼티를 저장함.
- [ ] <<AI>> 추출된 프로퍼티가 존재하는 상태일 때, 사용자가 해당 Entry를 조회하면, 자동 프로퍼티를 필터·정렬·검색 조건으로 활용할 수 있게 함.
- [ ] <<AI>> 추출이 실패한 상태일 때, 시스템이 실패를 기록하면, 실패 원인과 대상 Entry를 오류 상세로 조회 가능하게 함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `88`
