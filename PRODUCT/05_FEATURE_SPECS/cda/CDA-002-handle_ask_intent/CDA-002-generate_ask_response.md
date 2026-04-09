---
interaction_id: "CDA-002-generate_ask_response"
interaction_type: "background"
feature: "Handle Ask Intent"
category_key: "CDA"
feature_id: "CDA-002"
status: "기획 완료"
summary: "생성된 컨텍스트 기반으로 LLM을 호출해 자연어 문장 형태의 Reponse를 생성"
related_region: "-"
menu: "-"
shortcut: "-"
---

# Generate Ask Response

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- Ask Context가 준비된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- Ask Context에 포함된 컨텍스트 양이 많아 응답 생성이 오래 걸리거나 부분 응답만 생성되는 경우

## Acceptance Criteria

- [ ] <<AI>> Ask Context가 준비된 상태일 때, Generate Ask Response 인터랙션이 실행되면, Ask Intent로
      분류된 Chunk와 Ask Context를 바탕으로 질문에 대한 자연어 응답 텍스트가 생성되고 해당 User
      Request Message에 연결됨.
- [ ] <<AI>> Ask Context에 포함된 컨텍스트 양이 많아 응답 생성이 오래 걸리거나 부분 응답만 생성되는
      상태일 때, Generate Ask Response 인터랙션이 실행되면, 생성이 완료된 구간까지의 응답 텍스트가
      User Request Message에 저장되고, 응답이 부분적으로만 생성되었다는 상태 정보가 함께 기록됨.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `150`
