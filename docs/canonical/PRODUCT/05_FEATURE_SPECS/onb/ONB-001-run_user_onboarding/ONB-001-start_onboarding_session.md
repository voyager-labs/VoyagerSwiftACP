---
interaction_id: "ONB-001-start_onboarding_session"
interaction_type: "background"
feature: "Run User Onboarding"
category_key: "ONB"
feature_id: "ONB-001"
status: "배포 완료"
summary: "앱 실행 직후 온보딩 진입 필요 여부를 판정하고, 필요 시 온보딩 세션을 생성·초기화하며 재개 정책을 적용"
related_region: "onboarding_window"
menu: "-"
shortcut: "-"
---

# Start Onboarding Session

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- 온보딩을 완료하지 않은 상태
- 미완료 온보딩 진행 상태가 존재하는 상태
- 재온보딩이 필요한 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- 재온보딩이 필요한 상태인데, 기존 미완료 진행 상태가 함께 존재해 우선순위가 충돌하는 경우

## Acceptance Criteria

- [ ] 앱 실행 직후일 때, 온보딩이 필요한 상태라면, 온보딩 세션이 생성·초기화되고 첫 스텝 진입이
      준비됨
- [ ] 온보딩이 필요한 상태일 때, 재온보딩 필요 상태와 미완료 진행 상태가 동시에 존재한다면,
      재온보딩을 우선 적용함

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `239`
