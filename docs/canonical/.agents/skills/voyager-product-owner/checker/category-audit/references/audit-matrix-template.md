# Audit Matrix Template

카테고리 오디트 진행 상황을 추적하는 매트릭스 포맷.

오디트 시작 시 빈 매트릭스를 생성하고, 각 게이트 완료 후 셀을 업데이트한다.

## Column Headers

```
interaction_id | g0 | g0.5 | g1 | g2 | g3 | g4 | g5 | g6 | final
```

| Column | Gate | Description |
|---|---|---|
| `interaction_id` | - | FI에 등록된 interaction 식별자 |
| `g0` | Scope & Baseline | 스코프 확인, 매니페스트 작성 |
| `g0.5` | Source Availability | 참조 대상 존재 확인 |
| `g1` | Structural Lint | 결정론적 lint 통과 |
| `g2` | Implementation Status | status/phase가 코드와 정렬됨 |
| `g3` | Contract Alignment | contract/flow/어휘 정렬 |
| `g4` | Blind Clarity Review | 독립 에이전트 명확성 검증 |
| `g5` | Semantic Review | 11항목 의미 리뷰 |
| `g6` | Bundle Parity | FI/IA/FS 교차 레이어 정합성 |
| `final` | - | 전체 게이트 종합 판정 |

## Cell Values

| Value | Meaning | When Used |
|---|---|---|
| `P` | PASS | 게이트 기준을 모두 충족 |
| `NP` | NOT PASS | 기준 미충족, 수정 필요 |
| `N/A` | Not Applicable | 해당 게이트가 이 interaction에 적용되지 않음 |
| `out_of_scope` | 명시적 제외 | deprecated, 아직 작성 전 등 (사유 필수) |
| `SKIP` | 이전 게이트 NP | 선행 게이트가 NP라 진행 불가 |
| `(empty)` | 미실행 | 아직 해당 게이트에 도달하지 않음 |

## Category PASS Condition

카테고리 PASS를 선언하려면:

1. 모든 in-scope 셀이 `P`
2. `out_of_scope` 항목은 각 행에 사유가 주석으로 달려 있어야 함
3. `NP`, `SKIP` 셀이 0개
4. `(empty)` 셀이 0개 (모든 게이트가 실행 완료)

## Example: ONB Category

아래는 ONB 카테고리 오디트가 진행 중인 예시.
Gate 0, 0.5, 1은 완료, Gate 2부터 미실행.

```markdown
## ONB Audit Matrix

**Date**: 2026-05-17
**Auditor**: agent
**Status**: In Progress (Gate 1 완료, Gate 2 대기)

| interaction_id | g0 | g0.5 | g1 | g2 | g3 | g4 | g5 | g6 | final |
|---|---|---|---|---|---|---|---|---|---|
| ONB-001-welcome_screen | P | P | P | | | | | | |
| ONB-002-show_access_unlock_status | P | P | P | | | | | | |
| ONB-003-apply_access_unlock_result | P | P | P | | | | | | |
| ONB-004-update_onboarding_step_state | P | P | P | | | | | | |
| ONB-005-complete_onboarding | P | P | P | | | | | | |
| ONB-006-skip_onboarding | P | P | NP | | | | | | |

### Notes

- ONB-006: Gate 1 FAIL — section order violation. Fix pending.
```

## Example: Completed Audit

모든 게이트를 통과한 완료 예시:

```markdown
## CBW Audit Matrix

**Date**: 2026-05-15
**Auditor**: agent
**Status**: COMPLETE

| interaction_id | g0 | g0.5 | g1 | g2 | g3 | g4 | g5 | g6 | final |
|---|---|---|---|---|---|---|---|---|---|
| CBW-001-submit_chat_request | P | P | P | P | P | P | P | P | P |
| CBW-001-show_request_processing_state | P | P | P | P | P | P | P | P | P |
| CBW-001-cancel_active_chat_request | P | P | P | P | P | P | P | P | P |
| CBW-001-regenerate_chat_response | P | P | P | P | P | P | P | P | P |
| CBW-001-open_contextual_chat | P | P | P | P | P | P | P | P | P |
| CBW-004-show_available_chat_providers | P | P | P | P | P | P | P | P | P |
| CBW-004-select_active_chat_provider | P | P | P | P | P | P | P | P | P |
| CBW-004-open_chat_model_selector | out_of_scope | out_of_scope | out_of_scope | out_of_scope | out_of_scope | out_of_scope | out_of_scope | out_of_scope | out_of_scope |

### Notes

- CBW-004-open_chat_model_selector: `out_of_scope` — status=idea, phase=later. 구현 전 스펙으로 오디트 범위에서 제외.
- CBW-001-open_contextual_chat: Gate 5 WARN 1건 (Observability 섹션에 모니터링 지표 누락 권고). PASS 처리.
```

## How to Use

### 오디트 시작 시

1. FI에서 interaction_id 목록을 가져옴
2. 빈 행으로 매트릭스를 생성
3. `out_of_scope` 항목을 사유와 함께 미리 표시

### 각 게이트 완료 후

1. 해당 게이트 컬럼의 셀 값을 업데이트
2. NP가 발생하면 수정 후 재실행, P로 변경
3. 이전 게이트가 NP인 interaction은 다음 게이트를 `SKIP`으로 표시

### 오디트 완료 시

1. 모든 셀이 채워져 있는지 확인
2. `final` 컬럼: 모든 게이트가 P면 `P`, 하나라도 NP/SKIP이면 `NP`
3. Category PASS 조건을 검토하고 선언
