# Scoring Rubric

모든 게이트에서 공통으로 사용하는 P/NP 판정 기준.

## General PASS Conditions

모든 게이트에 공통으로 적용되는 PASS 조건:

1. **명시적(explicit)**: 애매함 없이 판정 근거를 설명할 수 있음
2. **SSOT 일치**: 판정이 FI, IA, contract 등 SSOT 문서와 일치함
3. **재현 가능**: 같은 입력으로 다시 실행하면 같은 결과가 나옴 (결정론적 게이트의 경우)
4. **문서화됨**: 판정 근거가 오디트 결과에 기록되어 있음

## General NOT PASS Conditions

모든 게이트에 공통으로 적용되는 NP 조건:

1. **모호(vague)**: "아마 괜찮을 것 같다" 수준의 판정
2. **모순(contradictory)**: 두 SSOT 소스가 서로 다른 값을 가리킴
3. **드리프트(drift)**: 마지막 오디트 이후 값이 변경되었지만 스펙에 반영되지 않음
4. **근거 부족**: 판정을 뒷받침하는 증거가 충분하지 않음

## Per-Gate Specific Criteria

### Gate 0: Scope and Baseline

| Condition | P | NP |
|---|---|---|
| FI에서 모든 interaction_id를 식별 | Yes | 누락된 ID가 있으면 NP |
| 매니페스트가 완전 | Yes | interaction_id가 빠져 있으면 NP |
| Baseline lint가 실행됨 | Yes | lint 실행 실패 시 NP |

### Gate 0.5: Source Availability

| Condition | P | NP |
|---|---|---|
| 모든 참조 대상 파일이 존재 | Yes | 끊어진 링크가 있으면 NP |
| contract 파일 최소 1개 | Yes | contract가 없으면 NP |
| flow 파일 (contract 있는 경우) | Yes | contract + flow 없음 = NP |
| WINDOW_STRUCTURE 참조 유효 | Yes | 없는 키 참조 = NP |

### Gate 1: Structural Lint

| Condition | P | NP |
|---|---|---|
| FAIL = 0 | Yes | FAIL >= 1 이면 NP |
| WARN 처리 | 기록만 하면 PASS | - |
| lint 스크립트 정상 종료 | Yes | 스크립트 에러 = NP |

### Gate 2: Implementation Status

| Condition | P | NP |
|---|---|---|
| shipped에 코드 존재 | Yes | 코드 없으면 NP |
| [now] 내용이 코드와 일치 | Yes | 드리프트 시 NP |
| [next]가 미구현 상태 | Yes | 이미 구현되어 있으면 NP |
| status/phase 조합이 타당 | Yes | 모순 시 NP |

### Gate 3: Contract Alignment

| Condition | P | NP |
|---|---|---|
| contract consistency FAIL = 0 | Yes | FAIL >= 1 이면 NP |
| 상태 어휘 일치 | Yes | 정의되지 않은 상태 참조 = NP |
| 소유권 경계 준수 | Yes | display가 writes = NP |
| CTA 레이블 일치 | Yes | 불일치 시 NP |

## Hard Fail Conditions

다음 조건 중 하나라도 충족되면 **어떤 게이트든 무조건 NP**. 수정 전까지 다음 게이트로
진행할 수 없다.

1. **FI TSV 컬럼 수 불일치**: 어떤 행이라도 헤더와 컬럼 수가 다름
2. **중복 interaction_id**: FI에 같은 ID가 두 개 이상 등장
3. **frontmatter 파싱 불가**: YAML이 깨져서 읽을 수 없음
4. **contract TOML 파싱 불가**: TOML 문법 오류로 스크립트가 읽을 수 없음
5. **필수 스키마 위반**: `schema.json`의 `required` 필드가 누락된 행
6. **빈 행 존재**: TSV에 빈 행이 있음 (repo 규칙 위반)

## WARN vs FAIL

| Severity | Meaning | Gate Progression |
|---|---|---|
| **FAIL** | 반드시 수정해야 함 | 다음 게이트로 진행 불가 |
| **WARN** | 수정 권장, 추후 검토 | 다음 게이트로 진행 가능 |
| **INFO** | 참고 사항 | 영향 없음 |

WARN 처리 규칙:
- WARN은 오디트 매트릭스에 메모로 기록
- 한 스펙에 WARN이 3개 이상이면 Gate 5에서 필수 검토 대상
- WARN을 "나중에"로 미루지 않고 반드시 기록

## Cell Values in Audit Matrix

| Value | Meaning |
|---|---|
| `P` | Gate PASS |
| `NP` | Gate NOT PASS (수정 필요) |
| `N/A` | 해당 게이트가 이 interaction에 적용되지 않음 |
| `out_of_scope` | 명시적 제외 (사유 필수) |
| `SKIP` | 이전 게이트 NP로 인해 스킵 |

`SKIP`은 Gate N이 NP일 때 Gate N+1 이후에 자동으로 표시. `SKIP` 셀이 있으면
카테고리 PASS 불가.

## Category PASS Condition

카테고리 PASS를 선언하려면:

1. 모든 in-scope interaction_id가 모든 게이트에서 `P`
2. `out_of_scope`로 표시된 항목은 사유가 명시되어 있음
3. `NP` 셀이 0개
4. `SKIP` 셀이 0개
5. hard fail 조건이 0개
