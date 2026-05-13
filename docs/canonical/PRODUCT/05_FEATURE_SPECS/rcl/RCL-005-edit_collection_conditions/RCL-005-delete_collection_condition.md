---
interaction_id: "RCL-005-delete_collection_condition"
interaction_type: "command"
feature: "Edit Collection Conditions"
category_key: "RCL"
feature_id: "RCL-005"
status: "배포 완료"
summary: "선택한 컨디션을 필터에서 제거"
related_region: "file_manager_window.content_pane.content_header.collection_filter_composer"
menu: "-"
shortcut: "⌫"
---

# Delete Collection Condition

## Intent

- 선택한 컨디션을 필터에서 제거.
- `RCL-005`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- 사용자가 condition chip을 추가하거나 property/operator/value를 변경할 때 호출된다.
- 사용자가 condition 삭제 입력을 실행할 때 호출된다.

## Preconditions

- Collection Filter Composer 또는 Collection page state가 초기화되어 있어야 한다.
- 현재 scope, query, condition draft를 읽고 갱신할 수 있어야 한다.

## Expected Outcome

- 선택한 컨디션을 필터에서 제거.
- condition은 registry가 허용하는 property, operator, value shape로 구성되어야 한다.
- 값 입력은 operator arity와 value type에 맞게 정규화되고, 실패하면 payload에 포함되지 않아야 한다.
- condition 변경 뒤에는 필요한 경우 applyFilters가 예약되어 결과 state를 갱신한다.

## State Changes

- conditions 배열, selected property/operator/value, validation error, applyFilters in-flight 상태를 갱신한다.
- property 변경 시 기존 operator/value가 새 property와 호환되지 않으면 안전한 초기 상태로 재설정한다.
- delete는 선택된 condition만 제거하고 남은 condition 순서를 유지한다.

## User-visible Feedback

- 중복 property 추가, 값 필수 누락, 숫자/날짜 파싱 실패, range 역전은 condition chip 안에서 즉시 표시한다.
- condition 삭제 또는 변경 후 결과 적용 중이면 loading feedback을 유지한다.

## Edge Cases / Failure Handling

- 이미 추가된 property는 중복 추가를 막고 안내한다.
- operatorValueArity가 0이면 value 없이 `null` payload로 전송할 수 있다.
- unknown key가 appliedFilters로 돌아오면 비활성 condition으로 남겨 원인을 확인할 수 있게 한다.
- 명령 실행 중 실패하면 대상 상태를 부분 적용된 것처럼 표시하지 않는다.

## Acceptance Criteria

- [ ] 새 condition을 추가하면 property 선택 가능한 draft condition이 생성되어야 한다.
- [ ] operator를 바꾸면 value 입력 UI와 arity가 registry 기준으로 바뀌어야 한다.
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
- [RCL-005-change_collection_condition_value](RCL-005-change_collection_condition_value.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:134`
- Implementation references: `../voyager-app/docs/features/composer.md`, `../voyager-app/docs/features/entries-collections.md`, `../voyager-app/apps/macos/Voyager/Voyager/04_Features/Composer/Reducer/ComposerFeature.swift`, `../voyager-app/apps/macos/Voyager/Voyager/05_Entities/Collection/Reducer/CollectionFeature.swift`
- Flows: [collection_condition_editing_flow.md](../flows/collection_condition_editing_flow.md)
