# Semantic Review Checklist

Use this checklist when `feature-spec-reviewer` reviews interaction specs for a single `feature_id`.

Each check applies to every interaction spec file under the target feature directory.

For every finding, the reviewer must provide a **specific fix recommendation** — not just "this is wrong" but the exact before/after change needed.

## 1. FI ↔ Frontmatter Alignment

Verify that the interaction spec's YAML frontmatter matches the corresponding INTERACTIONS TSV row exactly.

| Frontmatter field | TSV column | Match type |
|---|---|---|
| `interaction_id` | col 2 | exact |
| `interaction_type` | col 3 | exact |
| `feature` | col 4 | exact |
| `category_key` | col 5 | exact |
| `feature_id` | col 6 | exact |
| `status` | col 7 | exact |
| `summary` | col 8 | exact (including `<<AI>>` markers) |
| `related_region` | col 9 | exact |
| `menu` | col 10 | exact |
| `shortcut` | col 11 | exact |

**Severity**: FAIL for any mismatch.

**Note**: The deterministic bundle checker (`check_feature_bundle.py`) catches most of these. If it passed clean, this check can be a quick confirmation rather than a full re-verification.

## 2. Contract Ownership Compliance

For each interaction, verify that the behavior described in the spec body does not exceed the permissions granted by the contract's `[ownership."<interaction_id>"]` section.

### What to check

1. **State Changes**: If the spec says "saves to `progress_snapshot`" or "writes X to Y", the contract's `writes` array must include the corresponding state.
2. **Preconditions**: If the spec says "reads X", the contract's `reads` array must include X.
3. **display interactions**: Contract should have `writes = []`. If the spec's State Changes section says it writes anything, that's a FAIL.

### Example violation

Contract:
```toml
[ownership."ONB-002-show_access_unlock_status"]
reads = ["pending", "complete", "blocked", "error"]
writes = []
```

Spec State Changes:
```
- 마지막 확인 시각과 마지막 오류 상태를 `progress_snapshot`에 반영할 수 있어야 한다.
```

→ **FAIL**: display interaction claims write behavior but contract says `writes = []`.

**Fix**: Remove the write claim from the display spec. If the timestamp/error recording is needed, move it to the interaction that owns the write (e.g., `apply_access_unlock_result` or `update_onboarding_step_state`).

**Severity**: FAIL.

## 3. State Vocabulary Scope

Each interaction spec should only reference states that are relevant to its scope, not the entire category vocabulary.

### What to check

1. **Boundary Notes**: If the spec says "ONB step status vocabulary는 `pending`, `complete`, `blocked`, `error`, `skipped`를 따른다", verify that the feature actually uses all listed states.
2. **Contract status declarations**: Check the category-specific contract (not just the session contract) for which states exist. If the category contract has `allowed = ["pending", "complete", "blocked", "error"]` but no `skipped`, listing `skipped` in Boundary Notes is inaccurate.

### Example violation

`access_unlock_contract.toml` defines states: `pending`, `complete`, `blocked`, `error` (no `skipped`).

Spec Boundary Notes: "ONB step status vocabulary는 `pending`, `complete`, `blocked`, `error`, `skipped`를 따른다."

→ **WARN**: `skipped` is not an Access Unlock state. The Boundary Note overclaims the vocabulary scope.

**Fix**: Change Boundary Notes to list only the states this feature owns. In this case: "ONB step status vocabulary는 `pending`, `complete`, `blocked`, `error`를 따른다."

**Severity**: WARN.

## 4. Observability Adequacy

Check each interaction's `## Observability / Analytics` section against these rules from the spec writing guide:

> - Describe events worth tracking, such as entry, success, failure, and retry.
> - Prefer observable checkpoints over implementation plumbing.
> - Do not invent analytics for trivial shell, display, or navigation interactions when the product does not need a distinct event.
> - When no observability or analytics requirement is intentionally defined, write `-` to mark deliberate not-applicable status.

### What to check

1. **Interaction-specific**: Each interaction should list events it owns, not events owned by sibling interactions.
2. **Not copy-pasted**: If two or more interactions have identical Observability items, at least one is wrong — each interaction has a different scope.
3. **Not over-inflated**: A background or command interaction should list entry/success/failure/retry. A trivial display interaction may just have `-`.
4. **Follows the guide pattern**: Compare against the best examples in the codebase (e.g., `ONB-001-start_onboarding_session`: 4 specific, interaction-scoped items).

### Example violations

**Copy-paste across interactions**:
- `complete_onboarding_session` and `resume_onboarding_session` both list the same 5 items including "온보딩 세션 시작/재개/완료" → resume doesn't own "시작" or "완료", and complete doesn't own "시작" or "재개".

**Fix**: Scope each interaction's Observability to what it actually does:
- complete: "온보딩 세션 완료 처리 성공/실패", "File Manager Window 오픈 성공/실패"
- resume: "온보딩 세션 재개 성공/실패", "snapshot 복원 성공/실패", "stale snapshot fallback 발생"

**Missing section entirely**:
- `update_onboarding_step_state` has no `## Observability / Analytics` section at all, jumping from Permissions straight to Related Interactions → section is missing.

**Fix**: Add the missing section between Permissions and Related Interactions with interaction-specific items.

**Severity**: WARN.

## 5. Boundary Notes Accuracy

Boundary Notes should accurately describe what the interaction owns and what it delegates.

### What to check

1. **Ownership claims match contract**: If Boundary Notes say "이 interaction은 X를 소유하지 않는다", verify the contract agrees.
2. **Delegation claims match reality**: If Boundary Notes say "X는 외부 flow에 위임한다", verify the spec body and contract don't give this interaction ownership of X.
3. **Vocabulary claims match contract**: See check 3 above.

**Severity**: WARN for overclaiming, FAIL for directly contradicting the contract.

## 6. Source Section Completeness

Each interaction spec's `## Source` section should list all relevant upstream documents.

### Required lines

| Line | When required |
|---|---|
| `Inventory row:` | Always. Format: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:<line>` |
| `Contracts:` | When any category-level contract is relevant. Link to all applicable `contracts/*.toml` files. |
| `Flows:` | When any category-level flow directly sequences this interaction. Link to the relevant `flows/*.md` files. |

### What to check

1. **Category-specific contracts**: If the category has a dedicated contract (e.g., `access_unlock_contract.toml`), it should be listed alongside the session-level contract. Missing the category contract is a finding.
2. **Flow references**: If the category flow doc's Interaction Coverage section lists this interaction, the spec should link back to that flow.
3. **No extra lines**: Source should only have `Inventory row:`, `Contracts:`, and `Flows:` lines. Implementation references, design notes, or code paths don't belong here.

### Example violation

Category has two contracts: `onboarding_session_contract.toml` and `access_unlock_contract.toml`.

The flow doc (`access_unlock_flow.md`) explicitly references `access_unlock_contract.toml` in its Contract References section.

But the spec only lists:
```markdown
- Contracts: [onboarding_session_contract.toml](../contracts/onboarding_session_contract.toml)
```

→ **WARN**: Missing `access_unlock_contract.toml` reference.

**Fix**: Add the missing contract reference:
```markdown
- Contracts: [onboarding_session_contract.toml](../contracts/onboarding_session_contract.toml), [access_unlock_contract.toml](../contracts/access_unlock_contract.toml)
```

**Severity**: WARN.

## 7. Interaction-Level Deduplication

Check that content specific to one interaction is not copy-pasted into sibling interactions.

### Where this typically happens

1. **Observability sections** — see check 4
2. **Expected Outcome** — listing outcomes that belong to the parent feature, not this specific interaction
3. **State Changes** — claiming state changes that the contract assigns to a different interaction

### How to detect

Read all interaction specs for the feature side by side. If two or more files have identical bullet points in the same section, at least one is likely wrong.

**Fix**: For each duplicated item, determine which interaction actually owns that behavior. Keep it only in the owning interaction. Replace it in the other with an interaction-scoped alternative or remove it.

**Severity**: WARN.

## 8. Section Completeness

Verify that every interaction spec has all required fixed sections in the correct order.

### Required sections (in order)

1. `Intent`
2. `Trigger / Entry Points`
3. `Preconditions`
4. `Expected Outcome`
5. `State Changes`
6. `User-visible Feedback`
7. `Edge Cases / Failure Handling`
8. `Acceptance Criteria`
9. `Permissions / Dependencies`
10. `Observability / Analytics`
11. `Related Interactions`
12. `Boundary Notes` (optional)
13. `Source`

### What to check

1. Every section is present (no accidental skips between Permissions and Related Interactions).
2. Sections are in the correct order.
3. No extra sections between the fixed ones.

The strict lint script (`lint_feature_spec.py --strict`) catches this, but a visual scan during semantic review catches cases where the section heading is present but the body is accidentally empty or misplaced.

**Severity**: FAIL for missing required sections, WARN for wrong order.

## 9. Contract Term Precision

Verify that interaction spec prose uses the exact terminology declared in the contract — not approximations, synonyms, or informal alternatives.

### Source rule (feature-spec-guide.md)

> - use the exact object names declared in the contract
> - use the exact allowed state names declared in the contract
> - do not use contract-forbidden state terms in interaction prose
> - do not invent alternate labels for the same object or state

### What to check

1. **State names in backticks**: When the spec references a state, it should use the exact contract key in backticks — e.g., `complete`, not 완료 or completed. The contract `[status.<key>]` declarations define the canonical names.

2. **Object names in backticks**: When the spec references a contract-declared object or concept, use the exact key — e.g., `progress_snapshot`, `access_status`, `step_completion_state`. Do not paraphrase as "진행 상태 저장소" or "접근 권한 결과" when the contract already names the concept.

3. **Policy values verbatim**: When the spec references a policy decision, use the exact value from the contract. For example, if the contract says `access_unlock_complete_for = ["core_license_active", "beta_code_trial_active", "internal_test_active"]`, the spec should list those exact values, not "유효한 라이선스", "활성 trial", "테스트 계정".

4. **No invented alternate names**: Do not introduce a synonym for an object or state that already has a contract-declared name. If the contract says `access_status`, do not also write "접근 상태 결과" or "unlock status" to mean the same thing.

### Example violations

**Imprecise state reference**:
```
- 현재 step이 완료되지 않았으면 Next는 실행되지 않는다.
```
→ The contract uses `complete` as the state name, not "완료".

**Fix**: Use the exact state key:
```
- 현재 step이 `complete`가 아니면 Next는 실행되지 않는다.
```

**Invented synonym for contract object**:
```
- 접근 권한 결과에 따라 다음 단계 진입 여부를 결정한다.
```
→ The contract defines this as `access_status`.

**Fix**: Use the contract term:
```
- `access_status`에 따라 다음 단계 진입 여부를 결정한다.
```

**Paraphrased policy value**:
```
- 유효한 라이선스나 trial이 확인되면 Access Unlock step이 완료된다.
```
→ The contract specifies exact values: `core_license_active`, `beta_code_trial_active`, `internal_test_active`.

**Fix**: Use the exact values:
```
- `core_license_active`, `beta_code_trial_active`, `internal_test_active`는 Access Unlock step complete로 반영된다.
```

**Severity**: WARN for first occurrence, FAIL if the same imprecise term appears repeatedly after being flagged.

## 10. Style and Tone Compliance

Verify that interaction spec prose follows the writing style rules from the feature-spec guide.

### Rules to check

1. **No vague hedge phrases** (feature-spec-guide.md line 33-34):
   - Forbidden for states, CTAs, triggers, or outcomes: `또는 동등한`, `유사한`, `적절한`, `필요 시`, `가능한 경우`, `등`
   - These are acceptable only when the ambiguity is intentional and part of the product contract.

2. **Exact state names and button labels** (feature-spec-guide.md line 35):
   - Prefer exact state names, button labels, UI regions, and trigger conditions.
   - When a UI label is known, use it verbatim — e.g., "Next", "Back", "Start Using", "Sign In", "Retry", not Korean translations unless the UI itself uses Korean.

3. **English label forms in body prose** (feature-spec-guide.md line 26-31):
   - In body prose, prefer stable English label forms over raw snake_case keys.
   - Example: prefer `request context`, `access status` in flowing prose, but keep `access_status` when referring to the literal contract key.
   - This rule does NOT apply to frontmatter `summary` — frontmatter follows FI row wording.

4. **No AI authoring artifacts** (feature-spec-guide.md line 17):
   - No internal comments, TODO notes, or generation instructions left in the document body.
   - `<<AI>>` markers are allowed only in frontmatter `summary` while the spec is still in draft status.

5. **One interaction per document** (feature-spec-guide.md line 18):
   - Each document covers exactly one `interaction_id`. If a document describes behavior belonging to another interaction, that content should be in the other document.

6. **Korean body prose with English terms** (feature-spec-guide.md line 37-38):
   - Body prose is in Korean.
   - Default user-visible labels, status names, CTA examples, and menu labels to English unless the product truth already establishes another literal label.
   - Do not translate a literal UI label into Korean if the UI itself uses English.

### Example violations

**Vague hedge phrase**:
```
- 사용자가 필요 시 재시도할 수 있다.
```
→ "필요 시" is a hedge phrase. Either the user can always retry, or there's a condition.

**Fix**: State the exact condition or remove the hedge:
```
- 사용자가 Retry를 실행하면 `access_status`를 다시 조회한다.
```

**Translating English UI labels to Korean**:
```
- 사용자가 '다음' 버튼을 누르면...
```
→ The UI button is "Next", not "다음".

**Fix**: Use the exact English UI label:
```
- 사용자가 Next를 실행하면...
```

**Raw snake_case in flowing prose where an English label would be more natural**:
```
- `step_completion_state`가 갱신된다.
```
→ In flowing prose, "step completion state" reads better unless referring to the literal contract key name for precision.

**Fix**: Depends on context. If this is a State Changes section talking about the contract field, keep backticks. If this is Intent or User-visible Feedback, prefer natural form:
```
- step completion state가 갱신된다.
```

**Severity**: WARN.

## 11. Acceptance Criteria Quality

Verify that Acceptance Criteria follow the required pattern and are testable.

### Required pattern (feature-spec-guide.md line 218-220)

```
<상황>에서, <행동>하면, <결과>해야 한다.
```

### What to check

1. **Pattern compliance**: Each AC follows the triple-clause pattern (situation → action → expected result).
2. **Testability**: Each AC describes one observable result that can be verified.
3. **State specificity**: Situations reference exact states (e.g., `complete`, `blocked`, `error`), not vague descriptions.
4. **One result per AC**: Each AC line scopes to one observable result, not multiple.

### Example violations

**Missing situation clause**:
```
- [ ] 사용자가 Next를 실행하면 다음 step으로 이동해야 한다.
```
→ No situation clause. What is the current state?

**Fix**: Add the situation:
```
- [ ] 현재 step이 `complete`인 상황에서 사용자가 Next를 실행하면, currentStep이 다음 step으로 변경되어야 한다.
```

**Multiple results in one AC**:
```
- [ ] step이 완료되면 snapshot이 저장되고 다음 step으로 이동하고 Next가 비활성화된다.
```
→ Three results in one AC.

**Fix**: Split into separate ACs:
```
- [ ] 현재 step이 `complete`인 상황에서 사용자가 Next를 실행하면, currentStep이 다음 step으로 변경되어야 한다.
- [ ] step 이동 시 snapshot 저장이 실패하면, 기존 currentStep을 유지하고 오류를 표시해야 한다.
```

**Severity**: WARN.

## Applying the Checklist

For each feature review:

1. Read all interaction specs, contracts, and flows in parallel.
2. Create a table with one row per interaction spec and columns for each checklist item (1-11).
3. Fill in ✅ / ⚠️ / ❌ for each cell.
4. For any ⚠️ or ❌, provide:
   - **File**: exact file path
   - **Section**: which section has the issue
   - **Issue**: what's wrong
   - **Fix**: the exact recommended change (before → after)
5. Summarize: total passed, total issues, severity breakdown.

### Fix guide format

Every finding must include a fix. Use this format:

```markdown
### ⚠️ <File> — <Section>

**Issue**: <what's wrong>

**Before**:
<exact current text>

**After**:
<exact replacement text>

**Reason**: <why this change is needed, referencing the contract or guide rule>
```

Do not report "everything looks fine" if you haven't actually checked each item against the source documents.
