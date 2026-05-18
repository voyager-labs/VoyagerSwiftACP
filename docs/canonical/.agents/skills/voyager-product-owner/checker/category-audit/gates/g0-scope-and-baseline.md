# Gate 0: Scope and Baseline

카테고리 오디트의 시작점. 스코프를 정의하고 현재 상태를 기록한다.

## Input

| Parameter | Example | Description |
|---|---|---|
| `category_key` | `ONB`, `SET`, `CBW` | 오디트 대상 카테고리 키 |

## Procedure

### 1. FI에서 interaction_id 수집

```bash
# INTERACTIONS TSV에서 해당 카테고리 행 추출
grep "^<CATEGORY>" PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv
```

TSV에서 추출:
- 모든 `interaction_id` (col 2)
- 각 행의 `status` (col 7)
- 각 행의 `phase` (col 8, 존재하는 경우)

### 2. 스펙 파일 맵핑

`PRODUCT/05_FEATURE_SPECS/<category>/` 아래에서 각 `interaction_id`에 대응하는
Markdown 파일을 찾는다.

파일 탐색 규칙:
- 패턴: `PRODUCT/05_FEATURE_SPECS/<category>/**/<interaction_id>*.md`
- 대소문자 무시
- 하나의 interaction_id에 여러 파일이 매칭되면 모두 포함

### 3. 베이스라인 lint 스냅샷

```bash
# 카테고리 내 모든 스펙에 대해 lint 실행, 결과 저장
python3 .agents/skills/voyager-product-owner/author/feature-spec/scripts/lint_feature_spec.py --strict \
  PRODUCT/05_FEATURE_SPECS/<category>/**/*.md
```

lint 출력을 그대로 기록한다. 이 시점에서 FAIL/WARN이 있어도 Gate 0은 통과할 수 있다.
베이스라인은 "현재 상태"를 나타낼 뿐이다.

### 4. 스코프 매니페스트 작성

결과를 매니페스트로 정리:

```markdown
## <CATEGORY> Scope Manifest

**Date**: YYYY-MM-DD
**Total interactions in FI**: N
**Spec files found**: M
**Missing specs**: K

| interaction_id | FI status | FI phase | Spec file | Baseline lint |
|---|---|---|---|---|
| ONB-001-welcome_screen | shipped | now | ONB-001-welcome_screen.md | PASS |
| ONB-002-show_access_unlock_status | drafted | now | (missing) | N/A |
```

## P/NP Criteria

### PASS

- FI에 등록된 모든 `interaction_id`를 식별했다
- 각 `interaction_id`에 대해 스펙 파일 존재 여부를 확인했다
- baseline lint 결과를 기록했다
- 매니페스트가 완성되었다

### NOT PASS

- FI 파싱 실패 (컬럼 수 불일치, 인코딩 문제 등)
- interaction_id를 식별할 수 없는 행이 존재
- 매니페스트가 불완전 (interaction_id 누락)

> **참고**: Gate 0은 "스펙이 없다"는 것 자체로 NP가 아니다. 없는 것을 매니페스트에 기록하면 된다.
> 스펙 누락에 대한 수정은 Gate 0.5에서 처리한다.

## Fix Protocol

이 게이트는 수정 자체가 목적이 아니라 현상 파악이 목적이다.

다만 다음 문제는 Gate 0에서 바로 수정:

1. **FI TSV 포맷 오류**: 컬럼 수 불일치, 빈 행 등 TSV 규칙 위반
   - `.agents/skills/voyager-product-owner/author/feature-inventory/references/tsv-writing-guide.md` 참조
2. **중복 interaction_id**: FI에 같은 ID가 두 번 이상 등장
   - 중복 제거 후 재실행

수정 후 매니페스트를 다시 작성한다.

## Commit Format

```
audit(<CATEGORY>): Gate 0 — scope manifest and baseline
```

## Output

1. **Scope manifest**: 매니페스트 마크다운 (커밋에 포함하거나 오디트 결과에 첨부)
2. **Baseline lint snapshot**: lint 실행 결과 전문
3. **Gate 0 result**: P or NP
4. **Audit matrix**: `references/audit-matrix-template.md` 형식에 맞춰 Gate 0 컬럼 채움

다음 게이트로 전달하는 데이터:
- `interaction_ids[]`: FI에서 식별된 전체 ID 목록
- `spec_file_map{}`: interaction_id → 파일 경로 매핑
- `missing_specs[]`: 스펙 파일이 없는 interaction_id 목록
