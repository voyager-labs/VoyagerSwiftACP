---
interaction_id: "RCL-004-submit_collection_filter_query"
interaction_type: "command"
feature: "Compose Collection Filter"
category_key: "RCL"
feature_id: "RCL-004"
status: "배포 완료"
summary: "텍스트필드에 입력된 쿼리를 제출해 필터 생성 파이프라인을 시작"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "⏎"
---

# Submit Collection Filter Query

## Intent

- Collection Filter Composer의 자연어 입력을 현재 필터 조건 변경 흐름으로 넘겨 사용자가 개별 조건을 일일이 손보기 전에 원하는 조건 구성을 빠르게 만들 수 있게 한다.

## Trigger / Entry Points

- Collection Filter Composer의 입력 필드에서 Enter를 눌렀을 때
- 입력 필드에 포커스가 있는 상태에서 제출 CTA를 호출했을 때

## Preconditions

- Collection Filter Composer가 열린 상태
- Filter Query 입력 필드가 포커스된 상태
- 입력값이 존재하는 상태
- 현재 Composer에 대해 더 새로운 제출이 이미 진행 중이지 않은 상태

## Expected Outcome

- 방금 입력한 내용이 하나의 제출로 확정되고, 시스템이 이를 기준으로 적용 가능한 조건 변경 결과를 만들기 시작한다.
- 이전 실패 피드백이 남아 있더라도 새 제출은 가장 최근 시도를 기준으로 다시 시작된다.

## State Changes

- `editable` -> `query_submitting`
    - 사용자가 입력 내용을 제출하면 시스템이 현재 Composer 문맥을 가장 최근 제출 기준의 처리 상태로 전환한다.
- `conversion_failure_feedback_visible` -> `query_submitting`
    - 직전 변환 실패 안내가 표시 중이어도 새 제출이 시작되면 실패 안내는 새 제출 흐름 기준으로 다시 정리된다.
- `execution_failure_feedback_visible` -> `query_submitting`
    - 직전 실행 실패 feedback 이후에도 사용자는 동일 필드에서 즉시 재제출할 수 있다.

## User-visible Feedback

- submit 직후 사용자는 입력이 처리 중이라는 사실을 이해할 수 있어야 한다.
- 기존 실패 안내가 표시 중이었다면, 새 제출 이후에는 이전 안내가 현재 제출 흐름의 의미를 가리지 않아야 한다.

## Edge Cases / Failure Handling

- 직전과 동일한 내용을 연속으로 제출하는 경우
- 더 오래된 제출 결과가 늦게 도착하는 경우
- 현재 조건 구성과 비교해 실질 변경이 없는 질의를 다시 제출하는 경우
- 기존 조건 구성을 유지하는 결과로 성공했지만 화면상 내용이 그대로 남는 경우

## Acceptance Criteria

- [ ] 텍스트필드에 값이 존재하는 상태에서, 사용자가 해당 인터랙션을 호출하면 시스템이 방금 입력한 내용을 기준으로 필터 구성 흐름을 시작해야 한다.
- [ ] 같은 Composer 문맥에서 이미 더 새로운 제출이 진행 중이라면, 시스템이 더 오래된 제출 결과를 현재 상태로 채택하지 않아야 한다.
- [ ] 사용자가 직전과 동일한 내용을 연속 제출했을 때, 시스템은 중복 실행처럼 보이지 않게 처리하되 최신 제출 시도 자체를 무시해서는 안 된다.
- [ ] 제출 이후 결과가 실질 변경 없음 또는 기존 조건 구성 유지로 귀결되더라도, 시스템은 이를 제출 실패로 취급하지 않아야 한다.
- [ ] 직전 failure feedback이 표시 중이더라도, 사용자는 같은 입력 필드에서 즉시 다시 submit할 수 있어야 한다.

## Permissions / Dependencies

- Query 해석 흐름이 현재 Composer 문맥에서 가장 최근 제출이 무엇인지 추적할 수 있어야 한다.
- submit은 저장된 콜렉션을 다시 여는 경고 경로가 아니라 Composer 안의 일반 query 제출 경로에서만 사용된다.

## Observability / Analytics

- query 제출 시점에 가장 최근 제출 여부와 Composer 문맥을 함께 구분할 수 있어야 한다.
- 이후 결과가 정상 반영 / 실질 변경 없음 / 기존 조건 구성 유지 / 변환 실패 / 실행 실패 중 어느 경로로 끝났는지 추적 가능해야 한다.

## Related Interactions

- [RCL-004-type_collection_filter_query](RCL-004-type_collection_filter_query.md)
- [RCL-004-generate_filter_changes_from_query](RCL-004-generate_filter_changes_from_query.md)
- [RCL-004-apply_generated_filter_changes](RCL-004-apply_generated_filter_changes.md)
- [RCL-004-show_query_conversion_failure_feedback](RCL-004-show_query_conversion_failure_feedback.md)
- [RCL-004-show_query_execution_failure_feedback](RCL-004-show_query_execution_failure_feedback.md)
- [RCL-004-coalesce_repeated_query_failure_feedback](RCL-004-coalesce_repeated_query_failure_feedback.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:107`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md)
