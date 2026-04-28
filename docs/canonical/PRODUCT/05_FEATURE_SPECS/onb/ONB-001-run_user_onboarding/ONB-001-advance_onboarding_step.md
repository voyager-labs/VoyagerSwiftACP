---
interaction_id: "ONB-001-advance_onboarding_step"
interaction_type: "input"
feature: "Run User Onboarding"
category_key: "ONB"
feature_id: "ONB-001"
status: "배포 완료"
summary: "현재 스텝의 완료 조건(FDA, Launch at Login 등)을 검증하고, 다음 스텝으로 이동"
related_region: "onboarding_window"
menu: "-"
shortcut: "-"
---

# Advance Onboarding Step

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 온보딩 스텝이 표시된 상태
- 현재 스텝에서 다음 단계 이동 경로가 존재하는 상태
- 현재 스텝의 완료 조건이 충족된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- -

## Acceptance Criteria

- [ ] 현재 스텝의 완료 조건이 통과된 상태일 때, 해당 인터랙션을 호출하면, 다음 온보딩 스텝으로
      이동함
- [ ] 모든 입력을 완료했을 떄, 완료 조건이 미충족인 상태라면, 해당 인터랙션이 비활성화됨

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `242`
