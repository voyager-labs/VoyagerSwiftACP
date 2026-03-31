# Compute Video Embeddings

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EIX-018-compute_video_embeddings |
| Interaction Type | background |
| Feature | Compute Video Embeddings |
| Category Key | EIX |
| Feature ID | EIX-018 |
| Status | 아이디어 |
| Summary | 비디오 Entry의 전사 요약·키포인트와 화면 타입 정보를 입력으로 사용해 비디오 콘텐츠 의미를 표현하는 임베딩 벡터를 계산 |
| Related Region | - |
| Menu | - |
| Shortcut | - |

## Preconditions

- <<AI>> 대상 Entry가 비디오 계열 포맷으로 분류된 상태
- <<AI>> 전사 요약·키포인트 및 화면 타입 정보 등 임베딩 입력이 준비된 상태
- <<AI>> 임베딩 인덱싱 기능이 활성화된 상태
## Edge Cases

- <<AI>> 전사 생성 실패 또는 오디오 품질 문제로 입력이 부족한 경우
- <<AI>> 길이가 매우 길어 입력을 구간별로 축약해야 하는 경우
- <<AI>> 임베딩 계산 서비스 오류로 계산이 실패하는 경우

## Acceptance Criteria

- [ ] <<AI>> 비디오 Entry가 대상인 상태일 때, 시스템이 임베딩을 계산하면, 비디오 콘텐츠 의미 임베딩 벡터를 저장함.
- [ ] <<AI>> 임베딩이 저장된 상태일 때, 시스템이 인덱스를 갱신하면, 의미 기반 검색·유사도 판단에 해당 벡터를 활용할 수 있게 함.
- [ ] <<AI>> 계산이 실패한 상태일 때, 시스템이 실패를 기록하면, 실패 원인을 오류 상세로 조회 가능하게 함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `100`
