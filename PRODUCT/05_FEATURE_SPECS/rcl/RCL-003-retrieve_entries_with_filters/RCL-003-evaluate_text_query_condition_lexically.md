# Evaluate Text Query Condition Lexically

## Metadata

| Field            | Value                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------- |
| Interaction ID   | RCL-003-evaluate_text_query_condition_lexically                                       |
| Interaction Type | background                                                                            |
| Feature          | Retrieve Entries with Filters                                                         |
| Category Key     | RCL                                                                                   |
| Feature ID       | RCL-003                                                                               |
| Status           | 아이디어                                                                              |
| Summary          | 텍스트 쿼리 컨디션을 대상으로 키워드 매칭∙스코어링으로 평가해 키워드 매칭 신호를 생성 |
| Related Region   | -                                                                                     |
| Menu             | -                                                                                     |
| Shortcut         | -                                                                                     |

## Preconditions

- 텍스트 쿼리 컨디션 정의가 필터에 포함된 상태

## Edge Cases

- 키워드 매칭을 수행할 인덱스가 준비되지 않았거나 사용 불가한 상태인 경우
- 콜렉션 스코프가 넓거나 결정론 필터로 후보가 충분히 줄지 않아 평가 대상 엔트리 수가 과도하게 커지는
  경우

## Acceptance Criteria

- [ ] 후보 엔트리 집합이 산출된 상태일 때, 텍스트 쿼리 컨디션 정의가 필터에 포함된 상태라면, 키워드
      매칭과 스코어링을 수행해 엔트리별 키워드 매칭 신호를 생성함
- [ ] 키워드 매칭 신호를 생성할 때, 키워드 매칭을 수행할 자체 인덱스가 준비되지 않았거나 사용 불가한
      상태라면, OS 인덱싱 기반 검색으로 폴백해 키워드 매칭 신호를 생성함
- [ ] 키워드 매칭 신호를 생성할 때, 평가 대상 엔트리 수가 과도하게 커진다면, 성능 보호 정책을 적용해
      평가 범위를 제한한 뒤 키워드 매칭 신호를 생성함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `135`
