# Voyager Agent Harness Handoff v1

이 문서는 `voyager-documentation` 레포의 Codex subagents/skills 구성을 실제로 정리하는 담당 에이전트에게 넘기는 handoff 문서다.

목표는 단순히 agent를 몇 개 더 추가하는 것이 아니라, 어떤 모델을 쓰더라도 최대한 비슷한 구조와 diff가 나오도록 `결정론적 문서화 하네스`를 세우는 것이다.

## 1. North Star

이 레포에서 하네스의 핵심은 다음이다.

1. 결정론성은 모델이 아니라 `파이프라인`에서 만든다.
2. 자유 생성은 최소화하고, 후단은 가능한 한 `스크립트`, `템플릿`, `스키마`, `린터`로 고정한다.
3. 각 에이전트는 자유 서술보다 `정해진 산출물 타입`을 내야 한다.
4. 실제 파일 수정은 가급적 `single writer pattern`으로 모은다.
5. review는 “좋은 문장” 평가가 아니라 `gate 통과/실패` 평가여야 한다.

## 2. Repo Character To Optimize For

이 레포는 다음 성격을 가진다.

- Git-based SSOT
- PR-first
- TSV + schema + markdown 규율이 강함
- `-`, `TBD`, `<<AI>>` 규칙이 중요함
- feature bundle 단위의 정합성(FI/IA/FS)이 중요함

따라서 하네스는 “창의적 문서 작성기”보다 `입력 정규화 -> scope 분류 -> deterministic expansion -> semantic authoring -> validation` 구조에 맞춰야 한다.

## 3. Harness Principle: Contracts First

서브에이전트 이름보다 먼저 고정해야 하는 것은 `단계별 입출력 계약`이다.

권장 산출물 타입:

- `brief.yaml`
- `scope.json`
- `inventory_patch.tsvfrag`
- `ia_patch.tsvfrag`
- `use_case_patch.mdfrag`
- `spec_patch.mdfrag`
- `review_report.md`

각 단계는 이 중 하나만 산출하도록 좁게 설계한다.

## 4. Recommended End-State Pipeline

권장 파이프라인은 아래와 같다.

1. Intake
2. Scope classification
3. Deterministic expansion
4. Semantic authoring
5. Single writer apply
6. Validation
7. Review summary

### 4.1 Intake

입력:

- user raw request
- Linear issue
- Google Doc / Google Sheet / Google Slide requirement
- existing feature bundle context

출력:

- `brief.yaml`

담당:

- `product_interviewer`
- 또는 신규 `requirement_intake`

금지:

- 파일 수정
- TSV/markdown 직접 작성

### 4.2 Scope classification

입력:

- `brief.yaml`

출력:

- `scope.json`

담당:

- `scope_reviewer`

필수 포함 항목:

- `change_type`
- `touch_layers`
- `dont_touch_layers`
- `target_feature_ids`
- `required_decisions`
- `execution_order`

금지:

- 문안 작성
- 파일 수정

### 4.3 Deterministic expansion

입력:

- `scope.json`

출력:

- existing feature/interaction candidates
- generated draft skeleton paths
- exact missing references list

담당:

- repo-local scripts and checkers

대표 작업:

- `feature_id` 후보 탐색
- existing rows/spec lookup
- FEATURE_SPEC skeleton generation
- source line / related interactions sync
- consistency audit

중요:

- 이 단계는 가능한 한 `모델-free` 또는 `모델-light`여야 한다.
- 스크립트가 가능한 부분은 agent가 직접 쓰지 말고 script를 호출해야 한다.

### 4.4 Semantic authoring

입력:

- `scope.json`
- deterministic expansion 결과
- generated skeleton

출력:

- layer-specific patch proposal

담당:

- `inventory_author`
- `ia_author`
- `use_case_author`
- `spec_author`

원칙:

- 각 author는 자기 layer만 작성한다.
- 다른 layer는 건드리지 않는다.
- 자유 텍스트가 필요하더라도 출력은 patch fragment 중심으로 제한한다.

### 4.5 Single writer apply

입력:

- 모든 patch proposal

출력:

- 실제 파일 편집

담당:

- parent orchestrator
- 또는 dedicated `docs_writer`

원칙:

- 여러 subagent가 각자 파일을 직접 고치지 않는다.
- 최종 diff는 가능한 한 한 writer 단계에서만 발생시킨다.

### 4.6 Validation

입력:

- touched files
- touched feature ids

출력:

- pass/fail report

담당:

- checker scripts
- `bundle_reviewer`

대표 gate:

- TSV column count
- `-` / `TBD` / `<<AI>>` convention
- required frontmatter keys
- FEATURE_SPEC lint
- FI/IA/FS reference integrity
- stale source metadata

### 4.7 Review summary

출력:

- `review_report.md`

담당:

- `bundle_reviewer`
- 또는 parent orchestrator

원칙:

- findings first
- deterministic failures first
- semantic ambiguity는 별도 구분

## 5. Required Artifact Schemas

아래 스키마는 실제 handoff 이후 구현해야 하는 최소 계약이다.

### 5.1 `brief.yaml`

최소 필드:

```yaml
problem: ""
actor: ""
goal: ""
context: ""
in_scope: []
out_of_scope: []
evidence: []
ambiguities: []
source_inputs: []
```

규칙:

- `problem`, `actor`, `goal`, `in_scope`, `out_of_scope`는 비면 실패
- 애매한 내용은 prose로 숨기지 말고 `ambiguities`로 올린다

### 5.2 `scope.json`

최소 필드:

```json
{
  "change_type": "",
  "touch_layers": [],
  "dont_touch_layers": [],
  "target_feature_ids": [],
  "required_decisions": [],
  "execution_order": []
}
```

규칙:

- `touch_layers`가 비면 실패
- `dont_touch_layers`는 반드시 명시
- `execution_order`는 실제 orchestration order와 일치해야 함

### 5.3 Layer patch outputs

`inventory_patch.tsvfrag`

- FEATURES row 또는 INTERACTIONS row 단위
- 전체 파일 재작성 금지
- single-line TSV fragment 우선

`ia_patch.tsvfrag`

- WINDOW_STRUCTURE row 단위
- `structure_key` 관련 ref impact를 같이 명시

`spec_patch.mdfrag`

- frontmatter patch와 body section patch를 구분 가능해야 함

`use_case_patch.mdfrag`

- PREV/NEXT 영향과 흐름 변경 이유를 포함

### 5.4 `review_report.md`

권장 구조:

```md
## Findings
- FAIL:
- WARN:

## Synced
- ...

## Validation
- command:
- result:

## Open Decisions
- ...
```

## 6. Role Design: Keep Agents Narrow

### 6.1 Keep

유지할 기존 agents:

- `product_interviewer`
- `scope_reviewer`
- `inventory_author`
- `spec_author`
- `bundle_reviewer`
- `linear_issue_author`
- `product_researcher`

### 6.2 Add

추가 권장 agents:

- `ia_author`
- `use_case_author`
- `requirement_intake`
- optional: `docs_writer`

### 6.3 Responsibility Boundaries

`product_interviewer`

- 역할: fuzzy request를 `brief.yaml`로 정리
- 수정 금지

`requirement_intake`

- 역할: Linear/Docs/Slides 등 외부 입력을 repo-friendly brief로 정규화
- 수정 금지

`scope_reviewer`

- 역할: 어떤 문서 layer를 건드릴지 결정
- 수정 금지

`inventory_author`

- 역할: FEATURES / INTERACTIONS patch만 제안
- IA/FS/use case 수정 금지

`ia_author`

- 역할: WINDOW_STRUCTURE patch만 제안
- FEATURES/INTERACTIONS/spec 수정 금지

`use_case_author`

- 역할: USE_CASES patch만 제안
- inventory/spec 수정 금지

`spec_author`

- 역할: FEATURE_SPEC patch만 제안
- inventory row 직접 수정 금지

`docs_writer`

- 역할: 최종 diff 적용
- 가능하면 가장 작은 변경만 적용

`bundle_reviewer`

- 역할: findings and validation
- 기본 read-only

## 7. Model Policy

모델 선택은 자유롭게 두지 말고 역할별로 고정한다.

권장값:

- `product_interviewer`: `gpt-5.4`
- `requirement_intake`: `gpt-5.4`
- `scope_reviewer`: `gpt-5.4-mini`
- `inventory_author`: `gpt-5.4-mini`
- `ia_author`: `gpt-5.4-mini`
- `use_case_author`: `gpt-5.4-mini`
- `spec_author`: `gpt-5.4`
- `bundle_reviewer`: `gpt-5.4`
- `linear_issue_author`: `gpt-5.4-mini`

이유:

- 해석, ambiguity surfacing, semantic review는 큰 모델
- row drafting, layer classification, bounded authoring은 mini

중요:

- 모델보다 더 중요한 것은 동일한 output contract와 validation gate다

## 8. Sandbox Policy

권한도 역할별로 고정한다.

권장값:

- interviewer/researcher/reviewer/scope/intake: `read-only`
- author agents: `workspace-write` 또는 parent write inheritance를 명시적으로 허용
- `docs_writer`: `workspace-write`

주의:

- “edits allowed in prompt, but sandbox is read-only” 같은 자기모순을 만들지 않는다
- write 가능한 agent라도 가능한 한 실제 파일 수정은 `single writer`에 모은다

## 9. Config Policy

현재 `.codex/config.toml`은 아래 방향을 유지해도 된다.

- `max_threads = 4`
- `max_depth = 1`

해석:

- root orchestrator가 child를 부르는 현재 구조에 적합
- child가 다시 child를 부르는 nested orchestration은 기본 금지

단, 아래를 하고 싶으면 `max_depth = 2`를 검토할 수 있다.

- child author가 내부적으로 reviewer/checker child를 또 호출

기본 권장:

- 먼저 `max_depth = 1` 유지
- nested orchestration 필요성이 명확해진 뒤 늘릴 것

## 10. Skill Policy

서브에이전트보다 먼저 강화해야 할 것은 repo-local skill이다.

이 레포에서 skill은 단순 reference가 아니라 `절차와 명령어의 진짜 계약`이어야 한다.

우선순위:

1. `voyager-ia-author`
2. `voyager-use-case-author`
3. `voyager-requirement-intake`
4. `voyager-terminology-linter`
5. `voyager-pr-auditor`

### 10.1 `voyager-ia-author`

필수 포함:

- target file
- allowed columns
- `structure_key` ref rules
- `related_ui` / `related_region` impact check
- validation commands

### 10.2 `voyager-use-case-author`

필수 포함:

- target file layout
- PREV/NEXT editing rule
- flow section contract
- feature bundle relation rule

### 10.3 `voyager-requirement-intake`

필수 포함:

- allowed input sources
- output schema = `brief.yaml`
- no-write rule
- `must-update / consider-update / no-change` classification

### 10.4 `voyager-terminology-linter`

필수 포함:

- user-visible copy는 영어 우선
- state vocabulary consistency
- CTA naming consistency
- provider/capability naming consistency

### 10.5 `voyager-pr-auditor`

필수 포함:

- changed feature bundle 추출 규칙
- consistency checker 실행
- spec lint 실행
- compact report template

## 11. Integration Strategy

플러그인은 나중 문제다. 지금은 로컬 skill과 subagent 하네스가 먼저다.

도입 우선순위:

1. GitHub integration
2. Linear integration
3. Google Drive integration
4. Gmail integration

### 11.1 GitHub

가장 실무 효용이 높다.

목적:

- PR review automation
- repo-local AGENTS review guidance 활용

활용 포인트:

- docs typo나 TSV drift도 `Review guidelines`에 올리면 review focus로 강제 가능

### 11.2 Linear

다음 우선순위.

목적:

- issue intake
- implementation issue draft handoff
- Codex task delegation

중요:

- Linear는 source input 및 task trigger 용도
- SSOT write source는 아님

### 11.3 Google Drive

선택적.

목적:

- 외부 requirement intake
- 회의 노트, 기획 초안 읽기

주의:

- Google Drive는 편집 채널이 아니라 intake 채널로만 다룬다

## 12. Non-Negotiable Rules For The Implementing Agent

1. 역할 이름보다 `입출력 계약`을 먼저 구현하라.
2. 새 agent를 만들 때는 반드시 “입력 / 출력 / 금지사항 / allowed files”를 적어라.
3. 가능한 한 script가 할 수 있는 것은 agent prompt에 맡기지 마라.
4. write agent 수를 늘리지 마라.
5. validation 없는 authoring flow는 만들지 마라.
6. scope classification 없이 authoring으로 바로 뛰는 shortcut을 만들지 마라.
7. repo 규칙(`-`, `TBD`, `<<AI>>`, product-facing wording)을 각 agent prompt에 중복해서 흩뿌리기보다 skill과 validator에 최대한 집중시켜라.

## 13. Suggested Actual Build Order

이 순서로 구현하는 것을 권장한다.

### Phase 1: Contracts

- `brief.yaml` contract 문서화
- `scope.json` contract 문서화
- `review_report.md` template 문서화

### Phase 2: Missing skills

- `voyager-ia-author`
- `voyager-use-case-author`
- `voyager-requirement-intake`

### Phase 3: Missing agents

- `ia_author`
- `use_case_author`
- optional `docs_writer`

### Phase 4: Tighten current agents

- author 계열 `sandbox_mode` 명시
- reviewer 계열 read-only 명시
- README의 orchestration 예시 업데이트

### Phase 5: Validation harness

- PR auditor skill
- terminology linter
- feature bundle batch audit path

## 14. Definition Of Done

하네스는 아래를 만족하면 v1 완료로 본다.

1. fuzzy request가 `brief.yaml`로 수렴한다
2. 모든 작업이 `scope.json`을 거친다
3. FI/IA/FS/USE_CASES 각 layer에 owner가 있다
4. write path가 single writer 또는 single apply step으로 정리되어 있다
5. 모든 authoring flow에 deterministic validation step이 있다
6. 동일 요청을 서로 다른 모델로 실행해도 결과 구조와 touched layers가 거의 동일하다
7. review output이 prose가 아니라 `FAIL/WARN/INFO` 중심으로 수렴한다

## 15. Immediate Next Changes To Make

구성 담당 에이전트는 다음 액션부터 시작하는 것을 권장한다.

1. `.codex/agents/README.md`를 하네스 중심 설명으로 보강
2. `ia_author.toml` 추가
3. `use_case_author.toml` 추가
4. `requirement_intake.toml` 추가 또는 `product_interviewer`와 분리 여부 결정
5. `.agents/skills/` 아래 `voyager-ia-author`, `voyager-use-case-author`, `voyager-requirement-intake` 추가
6. 현재 author agents의 `sandbox_mode`를 명시적으로 정리
7. 향후 PR review용 `AGENTS.md` 하위 세분화 전략 수립

## 16. Final Instruction

이 handoff의 목적은 “에이전트를 많이 만드는 것”이 아니다.

목적은 다음 셋을 만족하는 문서화 하네스를 만드는 것이다.

1. 입력이 달라도 같은 구조로 수렴할 것
2. 모델이 달라도 같은 산출물 타입으로 수렴할 것
3. review가 취향이 아니라 deterministic gate 중심으로 수렴할 것

구현 중 선택이 필요하면 항상 아래 우선순위를 따른다.

1. deterministic contract
2. validation
3. narrow scope
4. single writer
5. model sophistication
