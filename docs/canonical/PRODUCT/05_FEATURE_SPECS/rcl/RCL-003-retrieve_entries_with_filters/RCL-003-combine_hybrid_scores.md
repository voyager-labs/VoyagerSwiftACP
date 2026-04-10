---
interaction_id: "RCL-003-combine_hybrid_scores"
interaction_type: "background"
feature: "Retrieve Entries with Filters"
category_key: "RCL"
feature_id: "RCL-003"
status: "아이디어"
summary: "키워드 매칭 신호와 의미적 유사도 신호를 가중 결합해 최종 관련도 스코어를 산출"
related_region: "-"
menu: "-"
shortcut: "-"
---

# Combine Hybrid Scores

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 키워드 매칭 신호 또는 의미적 유사도 신호 중 1개 이상이 존재하는 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 키워드 매칭 신호와 의미적 유사도 신호의 스코어 분포가 달라 결합 결과가 한쪽 신호에 과도하게
  치우치는 상태인 경우
- 한쪽 신호가 생성되지 않아 다른 신호만으로 최종 관련도 스코어를 산출하는 상태인 경우
- 가중 결합 정책이 유효하지 않아 안전한 기본 결합 정책으로 폴백해야 하는 상태인 경우

## Acceptance Criteria

- [ ] 키워드 매칭 신호 또는 의미적 유사도 신호가 생성된 상태일 때, 가중 결합을 수행하면, 엔트리별
      최종 관련도 스코어를 산출함
- [ ] 한쪽 신호가 결측인 상태에서, 가중 결합을 수행하면, 존재하는 신호만으로 최종 관련도 스코어를
      산출함
- [ ] 가중 결합을 수행할 때, 키워드 매칭 신호와 의미적 유사도 신호의 스코어 분포 차이로 결합 결과가
      한쪽에 치우칠 수 있는 상태라면, 결합 왜곡을 완화하는 정규화 정책을 적용함
- [ ] 가중 결합을 수행할 때, 가중 결합 정책이 유효하지 않은 상태라면, 안전한 기본 결합 정책으로
      폴백해 최종 관련도 스코어를 산출함

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `137`
