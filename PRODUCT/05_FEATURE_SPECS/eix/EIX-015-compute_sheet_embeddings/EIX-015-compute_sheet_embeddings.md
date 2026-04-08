# Compute Sheet Embeddings

## Metadata

| Field            | Value                                                                                                                       |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Interaction ID   | EIX-015-compute_sheet_embeddings                                                                                            |
| Interaction Type | background                                                                                                                  |
| Feature          | Compute Sheet Embeddings                                                                                                    |
| Category Key     | EIX                                                                                                                         |
| Feature ID       | EIX-015                                                                                                                     |
| Status           | 아이디어                                                                                                                    |
| Summary          | 스프레드시트 Entry의 시트 요약·주요 컬럼 설명·대표 행 예시 등을 입력으로 사용해 데이터셋 의미를 표현하는 임베딩 벡터를 계산 |
| Related Region   | -                                                                                                                           |
| Menu             | -                                                                                                                           |
| Shortcut         | -                                                                                                                           |

## Preconditions

- <<AI>> 대상 Entry가 시트 계열 포맷으로 분류된 상태
- <<AI>> 시트 요약·주요 컬럼 설명 등 임베딩 입력이 준비된 상태
- <<AI>> 임베딩 인덱싱 기능이 활성화된 상태

## Edge Cases

- <<AI>> 행·열이 매우 커서 대표 행/샘플을 선택해야 하는 경우
- <<AI>> 민감 정보가 포함되어 입력에서 마스킹·제외가 필요한 경우
- <<AI>> 임베딩 계산 서비스 오류로 계산이 실패하는 경우

## Acceptance Criteria

- [ ] <<AI>> 시트 Entry가 대상인 상태일 때, 시스템이 임베딩을 계산하면, 데이터셋 의미 임베딩 벡터를
      저장함.
- [ ] <<AI>> 임베딩이 저장된 상태일 때, 시스템이 인덱스를 갱신하면, 의미 기반 검색·유사도 판단에
      해당 벡터를 활용할 수 있게 함.
- [ ] <<AI>> 계산이 실패한 상태일 때, 시스템이 실패를 기록하면, 실패 원인을 오류 상세로 조회
      가능하게 함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `97`
