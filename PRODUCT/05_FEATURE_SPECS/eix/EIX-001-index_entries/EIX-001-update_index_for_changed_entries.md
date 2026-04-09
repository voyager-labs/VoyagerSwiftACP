---
interaction_id: "EIX-001-update_index_for_changed_entries"
interaction_type: "background"
feature: "Index Entries"
category_key: "EIX"
feature_id: "EIX-001"
status: "배포 완료"
summary: "수정·이동·삭제된 Entry를 감지해 해당 Entry에 대해 내용 기반 프로퍼티·임베딩 인덱스를 증분 갱신하거나 제거"
related_region: "-"
menu: "-"
shortcut: "-"
---

# Update Index for Changed Entries

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 파일 시스템 변경 이벤트를 수신한 상태
- 변경된 Entry가 인덱싱 대상이거나 기존 인덱스에 존재하는 상태
- Entry Indexing 진행이 일시 중지되지 않은 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 이동·이름 변경·수정 이벤트가 연속으로 발생해 이벤트 순서가 뒤섞이는 경우
- 변경 처리 중 대상 엔트리가 삭제되어 대상이 사라지는 경우
- 변경된 엔트리가 제외 규칙에 새롭게 매칭되어 대상에서 제외되는 경우

## Acceptance Criteria

- [ ] 파일 시스템 변경 감지가 활성화된 상태일 때, 시스템이 파일 시스템 변경 이벤트를 수신한다면,
      해당 유형에 맞는 증분 갱신 또는 제거 작업을 큐에 등록하고 실행 결과를 기록함
- [ ] 시스템이 변경 처리를 수행할 때, 이동·이름 변경·수정 이벤트가 연속으로 발생해 이벤트 순서가
      뒤섞인다면, 동일 엔트리에 대한 이벤트를 병합/정규화해 최종 상태 기준으로 인덱스를 갱신함
- [ ] 시스템이 변경 처리를 수행할 때, 변경 처리 중 대상 엔트리가 삭제되어 대상이 사라진다면, 오류로
      중단하지 않고 제거 작업으로 전환해 인덱스 항목을 정리함
- [ ] 시스템이 변경 처리를 수행할 때, 변경된 엔트리가 제외 규칙에 새롭게 매칭되어 대상에서
      제외된다면, 해당 엔트리를 인덱싱 큐와 검색 결과에서 제외하고 필요 시 인덱스 항목을 제거함

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `71`
