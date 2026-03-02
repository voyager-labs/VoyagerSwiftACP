# Route Chuncks to Intents

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | CDA-001-route_chuncks_to_intents |
| Interaction Type | background |
| Feature | Handle User Request |
| Category Key | CDA |
| Feature ID | CDA-001 |
| Status | 취소 |
| Summary | 분리된 각 Chunk의  내용을 분석해 적절한 Intent로 분류 |
| Related Region | - |
| Menu | - |
| Shortcut | - |

## Preconditions

- 대상 User Request Message에 하나 이상의 Chunk가 존재하는 상태
## Edge Cases

- 특정 Chunk 텍스트가 너무 짧거나 모호해 어떤 Intent로도 명확히 판별하기 어려운 경우
- 두 개 이상의 Intent 점수가 임계값 이상이면서 서로 근접해 단일 Intent로 결정하기 애매한 경우
- Chunk의 의도를 판별하기 위해 앞뒤 Chunk의 문맥을 함께 고려해야 하는 경우

## Acceptance Criteria

- [ ] -

## Source

- Inventory: `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `143`
