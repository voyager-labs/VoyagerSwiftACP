# Show Query Execution Failure Feedback

## Metadata

| Field            | Value                                                                                                                                    |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Interaction ID   | RCL-001-show_query_execution_failure_feedback                                                                                            |
| Interaction Type | display                                                                                                                                  |
| Feature          | Define Collection Filter                                                                                                                 |
| Category Key     | RCL                                                                                                                                      |
| Feature ID       | RCL-001                                                                                                                                  |
| Status           | 기획 완료                                                                                                                                |
| Summary          | 검색 실행 또는 Helper/XPC 계층 오류로 적용이 실패했을 때 입력 흐름을 막지 않는 가벼운 실패 피드백을 표시해 실패 원인을 구분할 수 있게 함 |
| Related Region   | file_manager_window.content_pane.content_header.collection_filter_composer                                                               |
| Menu             | -                                                                                                                                        |
| Shortcut         | -                                                                                                                                        |

## Preconditions

- Submit Collection Filter Query가 발생한 상태
- 현재 제출된 자연어 쿼리 또는 필터 적용 흐름에 대한 응답이 유효한 최신 요청 흐름에 속한 상태
- Generate Filter Changes from Query 또는 Apply Generated Filter Changes 이후 검색 실행 경로에서
  변환 실패 외의 실패가 발생한 상태
- Helper/XPC 계층 또는 검색 실행 계층 오류가 확인된 상태
- 저장된 collection open 실패 alert 경로가 아닌 일반 Composer 쿼리 제출 흐름인 상태

## State Transitions

- `query_submitting` -> `query_execution_failed`
    - 현재 쿼리 제출 또는 필터 적용 흐름이 실행 실패로 종료되면, 요청 체인이 실행 실패 상태로 전환됨
- `query_execution_failed` -> `execution_failure_feedback_visible`
    - 시스템이 사용자가 이해할 수 있는 고정 실패 문구로 non-blocking local feedback을 표시함
- `execution_failure_feedback_visible` -> `feedback_cleared`
    - 사용자가 typing / cancel / composer dismiss를 수행하면 현재 feedback이 즉시 정리됨
- `execution_failure_feedback_visible` -> `feedback_auto_dismissed`
    - 일정 시간이 지나면 현재 feedback이 자동으로 사라짐
- `execution_failure_feedback_visible` -> `query_resubmitting`
    - 사용자가 같은 필드에서 즉시 다시 제출하면, 기존 실행 실패 상태와 별개로 새 제출 상태로 전환됨

## Edge Cases

- 변환은 성공했지만 Apply Generated Filter Changes 이후 검색 실행이 실패하는 경우
- Helper unavailable과 일반 execution failure가 모두 동일한 실행 실패 문구로 처리되는 경우
- 오래된 요청 응답이 늦게 도착하는 경우
- 실패 피드백 표시 중 사용자가 연속 submit을 반복하는 경우
- 이전 feedback의 자동 해제가 새 feedback 표시 이후 늦게 도착하는 경우

## Acceptance Criteria

- [ ] Submit Collection Filter Query 이후 검색 실행 또는 Helper/XPC 계층 오류가 발생하면, 시스템이
      입력 흐름을 막지 않는 가벼운 실패 피드백을 Collection Filter Composer 영역에 표시함
- [ ] 시스템이 실패 피드백을 표시할 때, 실행 실패에 대응하는 고정 문구를 사용해 변환 실패와 구분되는
      의미의 메시지를 전달함
- [ ] 시스템이 피드백을 Composer 문맥 안의 독립적인 local toast 형태로 표시하고, 입력 흐름이나
      레이아웃을 방해하지 않음
- [ ] 오래된 요청 응답이 도착하더라도, 시스템이 현재 feedback 상태를 덮지 않음
- [ ] 시스템이 실행 실패 피드백을 표시하더라도, 사용자는 즉시 입력을 수정하거나 다시 제출할 수 있음
- [ ] 사용자가 typing / cancel / composer dismiss를 수행하면 현재 feedback이 즉시 정리됨
- [ ] 시스템이 표시 중인 feedback을 잠시 후 자동으로 정리하되, 이후 생성된 더 새로운 feedback을 잘못
      제거하지 않음
- [ ] 시스템이 동일 요청 체인에서 변환 실패와 실행 실패를 모두 감지할 수 있는 경우, 사용자가 마지막
      실패 원인을 식별할 수 있도록 실행 단계 기준 피드백을 우선 표시함
- [ ] 저장된 collection open failure는 이 인터랙션으로 로컬 토스트를 띄우지 않고, 기존 modal alert +
      rollback/reset 경로를 유지함
- [ ] 메인 앱에서 실제 실행 실패를 재현했을 때, 사용자가 Collection Filter Composer 상단 문맥에서
      local toast를 확인할 수 있음

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `111`
