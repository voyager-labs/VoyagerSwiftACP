# Coalesce Repeated Query Failure Feedback

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-001-coalesce_repeated_query_failure_feedback |
| Interaction Type | background |
| Feature | Define Collection Filter |
| Category Key | RCL |
| Feature ID | RCL-001 |
| Status | 기획 완료 |
| Summary | 동일한 실패 상태가 짧은 시간 안에 반복될 때 실패 피드백을 중복 누적하지 않고 노출 정책에 따라 합치거나 갱신함 |
| Related Region | - |
| Menu | - |
| Shortcut | - |

## Preconditions

- Show Query Conversion Failure Feedback 또는 Show Query Execution Failure Feedback이 표시 대상이 된 상태
- 현재 실패 피드백이 표시 중인 상태
- 짧은 시간 내 동일 유형의 실패가 반복 발생한 상태

## State Transitions

- `failure_feedback_visible` -> `repeated_same_failure_detected`
  - 동일한 실패 문구가 짧은 시간 내 반복 감지되면, 시스템이 새 실패를 중복 표시 후보로 식별함
- `repeated_same_failure_detected` -> `failure_feedback_coalesced`
  - 시스템이 동일 메시지 반복에 대해 새 feedback을 만들지 않고, 기존 토스트와 기존 자동 해제 시점을 그대로 유지함
- `failure_feedback_visible` -> `different_failure_detected`
  - 기존 feedback 표시 중 의미가 다른 실패 문구가 새로 감지되면, 시스템이 새 실패를 별도 의미의 상태로 분기함
- `different_failure_detected` -> `latest_failure_feedback_visible`
  - 시스템이 마지막 실패 유형에 맞는 feedback으로 교체하거나 갱신해 사용자가 최신 실패 원인을 식별할 수 있게 함
- `failure_feedback_visible` -> `feedback_auto_dismissed`
  - 일정 시간이 지나면 현재 feedback이 자동으로 사라짐
- `failure_feedback_visible` -> `feedback_cleared`
  - 사용자가 typing / cancel / composer dismiss를 수행하면 현재 feedback이 즉시 정리됨

## Edge Cases

- 오래된 요청 응답이 새 feedback 이후 늦게 도착하는 경우
- 동일한 실패가 매우 짧은 간격으로 연속 제출되는 경우
- 서로 다른 실패 유형이 교차 발생하는 경우
- 이전 실패 피드백의 자동 해제가 새 feedback 표시 이후 늦게 도착하는 경우
- 동일 메시지 반복 때문에 자동 해제 시점이 다시 시작되거나 연장되는 것처럼 보이면 안 되는 경우
- 실질적 필터 변경이 없는 경우가 사용자 feedback으로 과도하게 노출되면 안 되는 경우

## Acceptance Criteria

- [ ] 동일한 변환 실패 또는 동일한 실행 실패가 짧은 시간 내 반복되면, 시스템이 새 feedback을 만들지 않고 기존 토스트를 그대로 유지함
- [ ] 시스템이 dedupe 기준을 실패 문구 단위로 적용하고, 동일 메시지 반복에 대해서만 spam을 억제함
- [ ] 변환 실패와 실행 실패처럼 의미가 다른 실패 문구가 연속 발생하면, 시스템이 이를 하나로 뭉개지 않고 마지막 실패 문구 기준의 피드백으로 갱신함
- [ ] 오래된 요청 응답은 현재 feedback 상태를 바꾸지 않음
- [ ] 사용자가 typing / cancel / composer dismiss를 수행하면 현재 feedback이 즉시 정리됨
- [ ] 시스템이 표시 중인 feedback을 잠시 후 자동으로 정리하되, 동일 메시지 반복이 발생해도 기존 자동 해제 시점을 다시 시작하거나 연장하지 않음
- [ ] 시스템이 새로운 feedback이 이미 표시된 뒤에 도착한 이전 자동 해제로 인해 더 새로운 feedback을 잘못 제거하지 않음
- [ ] 실질적 필터 변경이 없는 경우는 내부 판단에만 사용되고, 사용자 피드백 대상으로 직접 확대되지 않음
- [ ] 사용자가 실패 후 입력을 수정해 재시도하는 동안에도, 시스템이 과도한 중복 노출 없이 현재 실패 상태만 이해할 수 있도록 피드백 수를 제어함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `112`
