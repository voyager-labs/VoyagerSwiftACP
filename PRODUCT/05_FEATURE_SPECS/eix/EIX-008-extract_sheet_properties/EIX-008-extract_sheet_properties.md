# Extract Sheet Properties

## Metadata

| Field            | Value                                                                                                                                |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Interaction ID   | EIX-008-extract_sheet_properties                                                                                                     |
| Interaction Type | background                                                                                                                           |
| Feature          | Extract Sheet Properties                                                                                                             |
| Category Key     | EIX                                                                                                                                  |
| Feature ID       | EIX-008                                                                                                                              |
| Status           | 아이디어                                                                                                                             |
| Summary          | 스프레드시트 Entry에서 시트 이름·주요 컬럼 헤더·행·열 수·간단 지표·요약 등 표 구조 기반 자동 프로퍼티를 추출해 Entry 프로퍼티로 저장 |
| Related Region   | -                                                                                                                                    |
| Menu             | -                                                                                                                                    |
| Shortcut         | -                                                                                                                                    |

## Preconditions

- <<AI>> 대상 Entry가 스프레드시트·테이블 계열 포맷으로 분류된 상태
- <<AI>> 시트 프로퍼티 추출 파이프라인이 활성화된 상태
- <<AI>> 대상 Entry를 읽을 수 있는 권한이 확보된 상태

## Edge Cases

- <<AI>> 시트가 암호화되어 있거나 권한 제한으로 내용을 읽을 수 없는 경우
- <<AI>> 행·열 수가 매우 커서 전체 로딩이 어려워 샘플링이 필요한 경우
- <<AI>> CSV 등에서 인코딩 문제로 컬럼 헤더 파싱이 실패하는 경우

## Acceptance Criteria

- [ ] <<AI>> 대상 Entry가 시트 포맷인 상태일 때, 시스템이 추출을 수행하면, 시트 이름·주요 컬럼
      헤더·행/열 수 등 자동 프로퍼티를 저장함.
- [ ] <<AI>> 추출 결과가 저장된 상태일 때, 사용자가 해당 Entry를 조회하면, 추출된 프로퍼티를
      검색·필터 조건으로 활용할 수 있게 함.
- [ ] <<AI>> 추출이 실패한 상태일 때, 시스템이 실패를 기록하면, 실패 원인과 대상 Entry를 오류 상세로
      조회 가능하게 함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `90`
