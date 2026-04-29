---
interaction_id: "RCL-002-save_collection_filter_changes"
interaction_type: "command"
feature: "Manage Retrieval Collections"
category_key: "RCL"
feature_id: "RCL-002"
status: "배포 완료"
summary: "현재 콜렉션 파일에 필터 변경 사항을 저장해 정의를 갱신"
related_region: "file_manager_window.content_pane.content_header.page_menu_area"
menu: "file_menu"
shortcut: "⌘⌥S"
---

# Save Collection Filter Changes

## Intent

- 현재 필터 조건의 미저장 변경을 collection 파일에 반영해, 사용자가 query 기반·수동 편집 결과를 이후 다시 열기 기준점으로 확정할 수 있게 한다.

## Trigger / Entry Points

- File 메뉴에서 save collection filter changes를 호출했을 때
- 현재 collection 문맥에 미저장 변경이 있고 저장 가능한 상태일 때 shortcut을 호출했을 때

## Preconditions

- 마지막 저장 상태 기준점이 존재하는 상태
- 현재 필터 조건 구성이 마지막 저장 기준점과 다른 상태
- 미저장 필터 변경이 존재하는 상태

## Expected Outcome

- 조건 구성이 유효하면 현재 collection 파일의 필터 조건 구성이 새 기준점으로 저장된다.
- 미완성 조건이 있으면 저장은 진행되지 않고 사용자는 Composer로 돌아가 해당 조건을 완성해야 한다.
- 저장 오류나 충돌이 나더라도 미저장 변경은 보존된다.

## State Changes

- `save_ready` -> `editable`
    - 저장이 성공하면 미저장 변경이 새 저장 기준점이 되고, 이후 사용자는 같은 Composer 문맥에서 추가 편집 또는 재제출을 이어갈 수 있다.
- `condition_value_incomplete` -> `save_blocked`
    - 미완성 condition이 있는 상태에서 save를 시도하면 저장은 차단된다.
- `save_ready` -> `save_failed`
    - 저장 오류 또는 충돌이 발생하면 미저장 변경을 유지한 채 실패 상태가 된다.

## User-visible Feedback

- 성공 시 사용자는 현재 필터 조건 구성이 저장되었다고 이해할 수 있어야 한다.
- 미완성 condition으로 save가 차단될 때는 저장 자체보다 condition completion이 먼저 필요하다는 피드백이 보여야 한다.
- 저장 오류 / 충돌은 미저장 변경을 잃지 않았다는 사실과 함께 전달되어야 한다.

## Edge Cases / Failure Handling

- 미완성 상태의 condition이 있는 경우
- 저장 중 저장 오류가 발생하는 경우
- 같은 collection이 다른 탭/윈도우에서 저장된 이후 현재 변경을 저장하려는 경우
- query 반영 직후 저장 가능한 상태가 되었지만 사용자가 추가 수동 수정 없이 바로 저장하는 경우

## Acceptance Criteria

- [ ] 저장된 collection 파일을 불러와 미저장 필터 변경이 존재하는 상황에서, 사용자가 해당 인터랙션을 호출하면 시스템은 현재 collection 파일의 필터 조건 구성을 현재 변경 사항으로 갱신하여 저장해야 한다.
- [ ] 미완성 condition이 존재하는 상황에서 save를 시도하면, 시스템은 저장을 진행하지 않고 해당 condition completion을 유도하는 피드백을 표시해야 한다.
- [ ] 저장 오류가 발생하면, 시스템은 미저장 변경을 유지한 채 실패 피드백을 표시해야 한다.
- [ ] 동일 collection이 다른 탭/윈도우에서 먼저 저장된 이후라면, 시스템은 현재 save를 완료로 오인하지 않고 conflict failure를 표시해야 한다.
- [ ] query 기반 반영 직후든 수동 값 편집 직후든, 유효한 미저장 조건 구성이면 동일 저장 경로를 사용해야 한다.

## Permissions / Dependencies

- 현재 collection 파일의 저장 권한과 마지막 저장 기준점 비교 정보가 필요하다.
- save는 현재 필터 조건 구성이 유효한지 판단할 때 `condition_value_incomplete` 상태를 직접 사용한다.

## Observability / Analytics

- 저장 성공 / 저장 차단 / 저장 실패를 분리해 기록할 수 있어야 한다.
- 저장 실패 원인이 미완성 / 저장 오류 / 충돌 중 무엇인지 구분 가능해야 한다.

## Related Interactions

- [RCL-004-apply_generated_filter_changes](../RCL-004-compose_collection_filter/RCL-004-apply_generated_filter_changes.md)
- [RCL-005-change_collection_condition_value](../RCL-005-edit_collection_conditions/RCL-005-change_collection_condition_value.md)
- [RCL-002-restore_saved_collection_snapshot](RCL-002-restore_saved_collection_snapshot.md)
- [RCL-002-open_saved_collection](RCL-002-open_saved_collection.md)
- [RCL-002-show_restored_collection_snapshot](RCL-002-show_restored_collection_snapshot.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:143`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md)
