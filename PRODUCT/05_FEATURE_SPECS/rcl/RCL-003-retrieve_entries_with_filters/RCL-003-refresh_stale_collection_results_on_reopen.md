---
interaction_id: "RCL-003-refresh_stale_collection_results_on_reopen"
interaction_type: "background"
feature: "Retrieve Entries with Filters"
category_key: "RCL"
feature_id: "RCL-003"
status: "기획 완료"
summary: "stale 상태의 저장된 콜렉션을 다시 열 때 복원된 snapshot을 먼저 보여준 뒤 필요한 경우에만 결과를 재계산해 갱신"
related_region: "-"
menu: "-"
shortcut: "-"
---

# Refresh Stale Collection Results on Reopen

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 저장된 콜렉션을 다시 여는 흐름이 시작된 상태
- 복원된 snapshot이 존재하지만 stale 상태로 판단된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- stale snapshot을 먼저 표시한 뒤 refresh가 실패하는 경우
- stale snapshot reopen 이후 사용자가 수동 refresh를 먼저 호출하는 경우
- 정의가 dirty하지 않아 refresh 성공 후 snapshot/meta write-back이 가능한 경우
- 정의가 dirty해서 refresh 성공하더라도 저장 파일을 다시 쓰면 안 되는 경우

## Acceptance Criteria

- [ ] stale 상태의 저장된 콜렉션을 다시 열 때, 시스템은 usable snapshot을 먼저 보여준 뒤 필요한
      경우에만 refresh를 enqueue함
- [ ] 시스템이 stale snapshot reopen 이후 refresh를 수행해 성공하면, stale 상태를 해제함
- [ ] refresh가 실패하면, 시스템은 stale 상태를 유지한 채 현재 결과 문맥을 계속 보여줄 수 있음
- [ ] refresh 성공 후 현재 정의가 dirty하지 않다면, 시스템은 최신 snapshot과 관련 메타데이터를 기존
      저장 파이프라인을 통해 다시 파일에 기록할 수 있음
- [ ] refresh 성공 후 현재 정의가 dirty하다면, 시스템은 최신 결과를 메모리상으로 갱신하더라도 저장
      파일 write-back은 수행하지 않음
- [ ] refresh 성공 후 write-back이 완료되면, 이후 reopen에서는 갱신된 snapshot/meta를 다시
      snapshot-first 복원에 사용할 수 있음

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `147`
