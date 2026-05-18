# Gate 1: Structural Lint

결정론적(deterministic) lint 패스. 스펙의 구조적 무결성을 기계적으로 검증한다.

## Input

Gate 0.5에서 검증된 스펙 파일 목록:

| Data | Description |
|---|---|
| `verified_specs[]` | 참조가 검증된 스펙 파일 경로 목록 |
| `category_key` | 오디트 대상 카테고리 |

## Procedure

### 1. 전체 스펙 lint 실행

```bash
python3 .agents/skills/voyager-product-owner/author/feature-spec/scripts/lint_feature_spec.py --strict \
  PRODUCT/05_FEATURE_SPECS/<category>/**/*.md
```

`--strict` 플래그를 반드시 사용한다. strict 모드에서는 WARN도 FAIL로 처리하지 않되,
WARN은 별도로 기록하여 추적 가능하게 한다.

### 2. 결과 파싱

출력에서 다음 항목을 분류:

- **FAIL**: 반드시 수정해야 하는 항목
- **WARN**: 수정을 권장하지만 Gate 1 통과를 막지는 않음
- **PASS**: 문제 없음

일반적인 FAIL 항목:
- YAML frontmatter 누락 또는 필수 필드 빠짐
- `interaction_id` 불일치
- 섹션 순서 오류 (예: `## State Changes`가 `## Observability` 뒤에 나옴)
- AC(Acceptance Criteria) 패턴 위반
- Source 섹션 포맷 오류

### 3. 스펙별 결과 정리

```markdown
## <CATEGORY> Lint Results

| interaction_id | File | FAIL | WARN | Status |
|---|---|---|---|---|
| ONB-001-welcome_screen | ONB-001-welcome_screen.md | 0 | 1 | PASS |
| ONB-002-show_access_unlock_status | ONB-002-show_access_unlock_status.md | 2 | 0 | NP |
```

FAIL 항목의 상세 내역을 별도로 기록:

```markdown
### ONB-002 FAIL Details

1. **Missing required field**: `interaction_type` not in frontmatter
2. **Section order**: "Observability" appears before "State Changes"
```

## P/NP Criteria

### PASS

- **FAIL 수 = 0**
- WARN이 있으면 문서화(기록)만 하고 통과 가능
- 모든 스펙 파일이 lint를 통과

### NOT PASS

- FAIL 항목이 1개 이상 존재
- lint 스크립트 자체가 에러로 종료

> **WARN 처리**: WARN은 Gate 1을 막지 않지만, 오디트 매트릭스에 별도 메모로 남긴다.
> WARN이 3개 이상인 스펙은 Gate 5에서 추가 검토 대상으로 표시한다.

## Fix Protocol

### frontmatter 문제

1. FI INTERACTIONS TSV에서 올바른 값을 확인
2. frontmatter 필드를 TSV 값과 일치시킴
3. 필수 필드 누락 시 TSV에서 값을 가져와 채움

필수 frontmatter 필드:
```yaml
---
interaction_id: "<ID>"
interaction_type: "action|display|system"
feature: "<feature_name>"
category_key: "<CATEGORY>"
feature_id: "<FEATURE_ID>"
status: "<status>"
summary: "<요약>"
related_region: "<structure_key>"
---
```

### 섹션 순서 문제

스펙 가이드에 정의된 순서대로 섹션을 재배치:

```
## Observability
## State Changes
## Boundary Notes
## Acceptance Criteria
## Source
```

참조: `.agents/skills/voyager-product-owner/author/feature-spec/references/feature-spec-guide.md`

### AC 패턴 위전

Acceptance Criteria가 Given/When/Then 형식을 따르도록 수정.

### Source 포맷 오류

Source 섹션이 지정된 포맷을 따르도록 수정.

### 수정 후 재실행

```bash
# 수정한 파일만 다시 lint
python3 .agents/skills/voyager-product-owner/author/feature-spec/scripts/lint_feature_spec.py --strict \
  <수정한_파일_경로>
```

FAIL이 0이 될 때까지 수정, 재실행을 반복.

## Commit Format

```
audit(<CATEGORY>): Gate 1 — structural lint PASS
```

## Output

1. **Lint report**: 전체 스펙의 FAIL/WARN/PASS 결과 테이블
2. **WARN tracking**: WARN 항목 목록 (향후 검토용)
3. **Gate 1 result**: P or NP
4. **Audit matrix**: Gate 1 컬럼 업데이트

다음 게이트로 전달하는 데이터:
- `lint_clean_specs[]`: lint를 통과한 스펙 파일 목록 (FAIL=0)
- `warn_specs[]`: WARN이 있는 스펙 목록 (Gate 5에서 재검토)
