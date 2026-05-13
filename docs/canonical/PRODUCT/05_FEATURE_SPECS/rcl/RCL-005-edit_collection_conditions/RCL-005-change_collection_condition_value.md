---
interaction_id: "RCL-005-change_collection_condition_value"
interaction_type: "input"
feature: "Edit Collection Conditions"
category_key: "RCL"
feature_id: "RCL-005"
status: "배포 완료"
summary: "선택한 컨디션의 비교 값 또는 범위를 편집해 해당 조건이 만족하는 엔트리 집합을 조정"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "-"
---

# Change Collection Condition Value

## Intent

- 선택한 컨디션의 비교 값 또는 범위를 편집해 해당 조건이 만족하는 엔트리 집합을 조정.
- `RCL-005`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- 사용자가 condition chip을 추가하거나 property/operator/value를 변경할 때 호출된다.
- 사용자가 condition 삭제 입력을 실행할 때 호출된다.

## Preconditions

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 scope, query, condition draft를 읽고 갱신할 수 있어야 한다.

## Expected Outcome

- 선택한 condition의 value를 operator arity와 value type에 맞게 정규화해 filter definition을 갱신한다.
- 단일 Date 조건은 absolute date, relative date, `Is today` operator를 허용한다.
- v1 Date range는 absolute date pair가 모두 입력된 경우에만 저장 가능한 값으로 취급한다.
- Recents 또는 Tags 후보는 `assisted_value_entry`로 값을 빠르게 채우는 보조 입력이며, 직접 입력을 대체하거나 차단하지 않는다.
- 값이 완성되면 `save_ready`, 절반만 채워졌거나 operator 요건을 만족하지 못하면 `condition_value_incomplete`로 이어진다.

## State Changes

- `editable`, `condition_value_incomplete`, `save_ready`를 읽고 같은 상태 집합을 다시 쓴다.
- Date range 한쪽 값만 있거나 value parsing이 실패하면 `condition_value_incomplete`를 유지한다.
- 완성된 값은 condition 배열과 filter definition에 반영하고, 저장 가능한 definition이면 `save_ready`를 만든다.
- property 변경 시 기존 operator/value가 새 property와 호환되지 않으면 안전한 초기 상태로 재설정한다.

## User-visible Feedback

- 중복 property 추가, 값 필수 누락, 숫자/날짜 파싱 실패, range 역전은 condition chip 안에서 즉시 표시한다.
- Date 입력은 absolute/relative/`Is today` 선택을 구분해 보여준다.
- Recents/Tags 후보가 비어 있거나 실패해도 직접 입력 필드는 유지한다.

## Edge Cases / Failure Handling

- Date range의 한쪽 값만 있으면 `condition_value_incomplete` 상태로 남기고 저장 가능한 값으로 취급하지 않는다.
- v1에서는 relative date pair를 range 저장 값으로 확장하지 않는다.
- operatorValueArity가 0이면 value 없이 `null` payload로 전송할 수 있다.
- unknown key가 appliedFilters로 돌아오면 비활성 condition으로 남겨 원인을 확인할 수 있게 한다.
- 입력이 유효하지 않으면 저장/적용을 실행하지 않고 수정 가능한 오류 상태를 유지한다.

## Acceptance Criteria

- [ ] Date 단일 조건은 absolute/relative/`Is today` 입력을 허용해야 한다.
- [ ] Date range 한쪽 값만 입력된 상황에서 저장을 시도하면 `condition_value_incomplete`/`save_blocked` 경로로 저장이 막혀야 한다.
- [ ] Recents/Tags 후보 입력이 실패해도 직접 값 입력은 계속 가능해야 한다.
- [ ] 값 검증에 실패하면 condition은 payload에 포함되지 않고 오류 메시지가 표시되어야 한다.

## Permissions / Dependencies

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 scope, query, condition draft를 읽고 갱신할 수 있어야 한다.
- 관련 UI region: `file_manager_window.content_pane.content_header.collection_filter_composer`

## Observability / Analytics

- interaction 실행 여부
- 요청/적용 성공 여부
- 실패 reason과 recovery action
- 마지막으로 적용된 filter snapshot

## Related Interactions

- [RCL-005-add_collection_condition](RCL-005-add_collection_condition.md)
- [RCL-005-change_collection_condition_operator](RCL-005-change_collection_condition_operator.md)
- [RCL-005-change_collection_condition_property](RCL-005-change_collection_condition_property.md)
- [RCL-005-delete_collection_condition](RCL-005-delete_collection_condition.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:133`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Implementation references: `../voyager-app/docs/features/composer.md`, `../voyager-app/docs/features/entries-collections.md`, `../voyager-app/apps/macos/Voyager/Voyager/04_Features/Composer/Reducer/ComposerFeature.swift`, `../voyager-app/apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`
- Flows: [collection_condition_editing_flow.md](../flows/collection_condition_editing_flow.md), [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md)
