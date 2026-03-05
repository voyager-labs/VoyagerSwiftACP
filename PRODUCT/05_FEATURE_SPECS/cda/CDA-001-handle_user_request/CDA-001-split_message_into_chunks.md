# Split Message into Chunks

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CDA-001-split_message_into_chunks |
| Interaction Type | background |
| Feature | Handle User Request |
| Category Key | CDA |
| Feature ID | CDA-001 |
| Status | 취소 |
| Summary | User Request Message를 의미 단위로 분리해, 이후 Intent의 기본 단위로 사용할 Chunk 목록을 생성 |
| Related Region | - |
| Menu | - |
| Shortcut | - |

## Preconditions

- 대상 User Request Message가 제출되어 처리가 시작되는 상태
## Edge Cases

- Message가 하나의 의미만 담고 있어 추가 분리가 실질적인 이득이 없는 경우
- 서로 다른 의미가 섞여 있지만 문장 구조가 애매해 의미 경계를 명확히 나누기 어려운 경우
- 앞뒤 문맥을 함께 봐야 의미가 드러나 Chunk를 과도하게 잘게 나눌 위험이 있는 경우

## Acceptance Criteria

- [ ] -

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `142`
