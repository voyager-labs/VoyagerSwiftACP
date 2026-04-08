# Show Query Conversion Failure Feedback

## Metadata

| Field | Value |
| --- | --- |
| Interaction ID | RCL-001-show_query_conversion_failure_feedback |
| Interaction Type | display |
| Feature | Define Collection Filter |
| Category Key | RCL |
| Feature ID | RCL-001 |
| Status | 기획 완료 |
| Summary | 자연어 쿼리 해석 단계에서 변환 실패가 발생했을 때 입력 흐름을 막지 않는 가벼운 실패 피드백을 표시해 반영되지 않은 이유를 이해할 수 있게 함 |
| Related Region | file_manager_window.content_pane.content_header.collection_filter_composer |
| Menu | - |
| Shortcut | - |

## Preconditions

- Submit Collection Filter Query가 발생한 상태
- 현재 제출된 자연어 쿼리에 대한 응답이 유효한 최신 요청 흐름에 속한 상태
- Generate Filter Changes from Query가 변환 실패로 종료된 상태
- 저장된 collection open 실패 alert 경로가 아닌 일반 Composer 쿼리 제출 흐름인 상태

## State Transitions

- `query_submitting` -> `query_conversion_failed`
  - 현재 쿼리 제출 흐름이 변환 실패로 종료되면, 요청 체인이 변환 실패 상태로 전환됨
- `query_conversion_failed` -> `conversion_failure_feedback_visible`
  - 시스템이 사용자가 이해할 수 있는 고정 실패 문구로 non-blocking local feedback을 표시함
- `conversion_failure_feedback_visible` -> `feedback_cleared`
  - 사용자가 typing / cancel / composer dismiss를 수행하면 현재 feedback이 즉시 정리됨
- `conversion_failure_feedback_visible` -> `feedback_auto_dismissed`
  - 일정 시간이 지나면 현재 feedback이 자동으로 사라짐
- `conversion_failure_feedback_visible` -> `query_resubmitting`
  - 사용자가 다시 제출하면 기존 feedback과 별개로 새 쿼리 제출 상태로 전환됨

## Edge Cases

- 오래된 요청 응답이 늦게 도착하는 경우
- 변환 실패 직후 사용자가 입력값을 수정해 다시 제출하는 경우
- 변환 실패와 실행 실패가 연속으로 발생하는 경우
- 실질적 필터 변경이 없는 경우에도 사용자 피드백으로 과도하게 확대하지 않아야 하는 경우
- 이전 feedback의 자동 해제가 새 feedback 표시 이후 늦게 도착하는 경우

## Acceptance Criteria

- [ ] Submit Collection Filter Query가 발생한 뒤 Generate Filter Changes from Query가 변환 실패로 종료되면, 시스템이 입력 흐름을 막지 않는 가벼운 실패 피드백을 Collection Filter Composer 영역에 표시함
- [ ] 시스템이 실패 피드백을 표시할 때, 변환 실패에 대응하는 고정 문구를 사용해 사용자가 왜 반영되지 않았는지 즉시 이해할 수 있게 함
- [ ] 시스템이 피드백을 Composer 문맥 안의 독립적인 local toast 형태로 표시하고, 입력 흐름이나 레이아웃을 방해하지 않음
- [ ] 오래된 요청 응답이 도착하더라도, 시스템이 현재 feedback 상태를 덮지 않음
- [ ] 시스템이 변환 실패 피드백을 표시하더라도, 사용자는 동일한 입력 필드에서 즉시 수정·재입력·재시도를 진행할 수 있음
- [ ] 사용자가 typing / cancel / composer dismiss를 수행하면 현재 feedback이 즉시 정리됨
- [ ] 시스템이 표시 중인 feedback을 잠시 후 자동으로 정리하되, 이후 생성된 더 새로운 feedback을 잘못 제거하지 않음
- [ ] 실질적 필터 변경이 없는 경우는 내부 판단에만 사용되고, 사용자 피드백 대상으로 직접 확대되지 않음
- [ ] 저장된 collection open 실패 경로에서 alert가 필요한 경우에는, 시스템이 이 인터랙션 대신 기존 alert 기반 경로를 유지함
- [ ] 메인 앱에서 실제 변환 실패를 재현했을 때, 사용자가 Collection Filter Composer 상단 문맥에서 local toast를 확인할 수 있음

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `110`
