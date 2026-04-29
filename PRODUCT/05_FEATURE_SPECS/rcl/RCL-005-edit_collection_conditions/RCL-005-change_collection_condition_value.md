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

- 사용자가 현재 필터 조건 안의 개별 값 또는 범위를 직접 다듬어 원하는 결과에 맞는 최종 조건 구성을 만들 수 있게 한다.

## Trigger / Entry Points

- Collection Filter Composer에서 기존 조건의 값 입력칸을 직접 편집했을 때
- Date condition에서 absolute / relative / `Is today` 편집 경로를 선택했을 때
- Recents 또는 Tags 기반 보조 후보를 눌러 value를 빠르게 채웠을 때

## Preconditions

- 편집 대상 조건이 존재하는 상태
- 해당 조건의 속성과 비교 방식이 설정된 상태
- 현재 Composer가 직접 값 편집을 허용하는 상태

## Expected Outcome

- 조건 값이 비교 방식의 의미에 맞게 갱신되고, 현재 필터 조건 구성이 즉시 새 의미를 반영한다.
- Date condition은 single-date relative 편집과 `Is today`를 허용하되, range는 v1에서 absolute pair가 모두 채워져야 한다.
- Recents/Tags 같은 보조 입력은 직접 입력을 대체하지 않고 보조 경로로만 동작한다.

## State Changes

- `editable` -> `save_ready`
    - 사용자가 유효한 값 편집을 마치면 현재 조건 구성이 미저장 상태이면서 저장 가능한 상태가 된다.
- `editable` -> `condition_value_incomplete`
    - 비교 방식의 요건을 아직 만족하지 못하면 현재 조건이 미완성 상태가 된다.
- `condition_value_incomplete` -> `editable`
    - 누락된 value가 모두 채워지면 미완성 상태가 해소되고 일반 편집 상태로 복귀한다.
- `save_ready` -> `save_ready`
    - 추가 value 보정이 이어져도 저장 가능한 유효 상태가 유지될 수 있다.

## User-visible Feedback

- 사용자는 값이 반영된 조건을 즉시 확인할 수 있어야 한다.
- 미완성 범위나 누락된 필수 값은 저장 가능한 정상 조건처럼 보이면 안 된다.
- Recents/Tags 후보가 비어 있거나 실패해도 직접 입력 경로는 계속 유지되어야 한다.

## Edge Cases / Failure Handling

- 범위 입력이 필요한데 한쪽 값만 채워지는 경우
- Date 조건에서 단일 상대 날짜와 절대 날짜 표시 방식을 전환하는 경우
- `Is today`처럼 별도 자유 입력값이 필요 없는 비교 방식을 선택하는 경우
- Recents/Tags 후보가 없거나 로드에 실패해도 사용자가 직접 입력을 계속해야 하는 경우

## Acceptance Criteria

- [ ] 해당 조건이 값 편집 상태인 상황에서, 사용자가 해당 인터랙션을 호출하면 시스템은 조건 값을 현재 비교 방식의 의미에 맞게 갱신해야 한다.
- [ ] Date 조건에서 사용자가 단일 상대 날짜 편집을 선택하면, 시스템은 상대 날짜 입력을 허용해야 한다.
- [ ] Date 조건에서 사용자가 `Is today`를 선택하면, 시스템은 별도 자유 입력값을 강제하지 않아야 한다.
- [ ] Date range 비교 방식인 상황에서 한쪽 절대 날짜 값만 입력되면, 시스템은 해당 조건을 `condition_value_incomplete` 상태로 유지해야 한다.
- [ ] Date range는 v1에서 absolute pair 입력만 허용해야 하며, relative range를 완성된 상태로 저장 가능하게 만들면 안 된다.
- [ ] Recents 또는 Tags 후보를 통해 값을 채울 수 있더라도, 시스템은 직접 입력 경로를 계속 허용해야 한다.
- [ ] Recents 또는 Tags 후보가 비어 있거나 실패하더라도, 시스템은 이를 별도 실패 경로로 승격하지 않고 직접 입력 경로를 유지해야 한다.

## Permissions / Dependencies

- 편집 대상 속성과 비교 방식 조합이 요구하는 값 형태를 판단할 수 있어야 한다.
- 보조 입력 후보는 선택 가능한 보조 경로이며, 부재 자체가 조건 편집을 막아서는 안 된다.

## Observability / Analytics

- 값 편집이 저장 가능한 유효 상태로 끝났는지, 미완성 상태로 남았는지 구분해 추적할 수 있어야 한다.
- 상대 날짜 / 절대 날짜 / `Is today` 사용 분기와 보조 입력 사용 여부를 확인할 수 있어야 한다.

## Related Interactions

- [RCL-005-add_collection_condition](RCL-005-add_collection_condition.md)
- [RCL-005-change_collection_condition_operator](RCL-005-change_collection_condition_operator.md)
- [RCL-005-change_collection_condition_property](RCL-005-change_collection_condition_property.md)
- [RCL-005-delete_collection_condition](RCL-005-delete_collection_condition.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:133`
- Contracts: [collection_filter_editing_contract.toml](../contracts/collection_filter_editing_contract.toml)
- Flows: [collection_filter_editing_flow.md](../flows/collection_filter_editing_flow.md)
