# Compute Image Embeddings

## Metadata

| Field            | Value                                                                                                              |
| ---------------- | ------------------------------------------------------------------------------------------------------------------ |
| Interaction ID   | EIX-016-compute_image_embeddings                                                                                   |
| Interaction Type | background                                                                                                         |
| Feature          | Compute Images Embeddings                                                                                          |
| Category Key     | EIX                                                                                                                |
| Feature ID       | EIX-016                                                                                                            |
| Status           | 아이디어                                                                                                           |
| Summary          | 이미지·스크린샷 Entry의 캡션·설명 텍스트와 시각적 특징을 입력으로 사용해 이미지 의미를 표현하는 임베딩 벡터를 계산 |
| Related Region   | -                                                                                                                  |
| Menu             | -                                                                                                                  |
| Shortcut         | -                                                                                                                  |

## Preconditions

- <<AI>> 대상 Entry가 이미지·스크린샷 계열 포맷으로 분류된 상태
- <<AI>> 캡션·설명 텍스트 또는 시각 특징 추출 결과가 준비된 상태
- <<AI>> 임베딩 인덱싱 기능이 활성화된 상태

## Edge Cases

- <<AI>> 이미지 디코딩 또는 특징 추출 실패로 입력이 부족한 경우
- <<AI>> 해상도가 매우 커서 다운샘플링 후 특징 추출이 필요한 경우
- <<AI>> 임베딩 계산 서비스 오류로 계산이 실패하는 경우

## Acceptance Criteria

- [ ] <<AI>> 이미지 Entry가 대상인 상태일 때, 시스템이 임베딩을 계산하면, 이미지 의미 임베딩 벡터를
      저장함.
- [ ] <<AI>> 임베딩이 저장된 상태일 때, 시스템이 인덱스를 갱신하면, 이미지 유사도·검색에 해당 벡터를
      활용할 수 있게 함.
- [ ] <<AI>> 계산이 실패한 상태일 때, 시스템이 실패를 기록하면, 실패 원인을 오류 상세로 조회
      가능하게 함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `98`
