# Compute Code Embeddings

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | EIX-014-compute_code_embeddings |
| Interaction Type | background |
| Feature | Compute Code Embeddings |
| Category Key | EIX |
| Feature ID | EIX-014 |
| Status | 아이디어 |
| Summary | 코드 Entry의 파일 구조·주요 심볼·주석 요약 등을 입력으로 사용해 코드 의미를 표현하는 임베딩 벡터를 계산 |
| Related Region | - |
| Menu | - |
| Shortcut | - |

## Preconditions

- <<AI>> 대상 Entry가 코드 계열 포맷으로 분류된 상태
- <<AI>> 코드 요약·구조 정보 등 임베딩 입력이 준비된 상태
- <<AI>> 임베딩 인덱싱 기능이 활성화된 상태
## Edge Cases

- <<AI>> 코드가 너무 크거나 의존 파일이 많아 요약/구조 추출이 제한되는 경우
- <<AI>> 바이너리·미니파이된 코드 등으로 의미 추출이 어려운 경우
- <<AI>> 임베딩 계산 서비스 오류로 계산이 실패하는 경우

## Acceptance Criteria

- [ ] <<AI>> 코드 Entry가 대상인 상태일 때, 시스템이 임베딩을 계산하면, 코드 의미 임베딩 벡터를 저장함.
- [ ] <<AI>> 임베딩이 저장된 상태일 때, 시스템이 인덱스를 갱신하면, 코드 유사도·검색에 해당 벡터를 활용할 수 있게 함.
- [ ] <<AI>> 계산이 실패한 상태일 때, 시스템이 실패를 기록하면, 실패 항목을 재시도 가능 상태로 유지함.

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `96`
