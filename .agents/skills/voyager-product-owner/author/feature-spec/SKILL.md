---
name: feature-spec-author
description: "Draft and concretize Voyager FEATURE_SPEC markdown documents from INVENTORY rows into the fixed interaction specification format, maintain required category flow docs alongside contract-backed specs, and handle explicit human-review handoff requests for a specific interaction spec such as '검토 완료로 넘겨줘' by syncing FS/FI AI markers and review status."
---

# Voyager Feature Spec Author

Create and refine concrete, consistently structured `PRODUCT/05_FEATURE_SPECS` documents.

In this repo:

- `FS` = `Feature Specs`
- `FI` = `Feature Inventory`

This skill writes and refines `FS` documents using `FI` rows as source inputs.
That includes both interaction spec files and the category-level flow docs that explain the end-to-end sequence through linked specs and contracts.

This skill sits inside `Phase 1. AI Draft Authoring` of the feature-spec lifecycle.
Use `.agents/skills/voyager-product-owner/orchestrator/references/feature-spec-authoring-lifecycle.md` as the route source of truth when deciding whether this skill should be authoring contracts, flows, interaction specs, or waiting on FI/IA work first.

This skill is useful when you need to:

- turn an `interaction_id` into a concrete FEATURE_SPEC draft,
- bring existing specs into the current frontmatter + fixed-section format,
- create or revise the category flow doc that keeps the same contract vocabulary across related interaction specs,
- mark one explicitly named interaction spec as human-reviewed and sync the matching FS/FI `<<AI>>` markers and review status,
- check that required sections and metadata fields are present before PR review.

## Resource Layout

- Use `assets/` for reusable output shells and any future applied examples that are meant to be adapted directly into new specs or flows.
- Keep `references/` for guides, workflows, rubrics, and contract-writing rules only.

## Policy Reminders

- Keep `SKILL.md` light; put detailed writing rules and contract/consistency workflow in the reference files.
- Follow the guide for shortcut notation, interaction links, ambiguity avoidance, exact UI labels, and AI-marker handling.
- Respect the authoring precedence defined in `references/feature-spec-guide.md`.
    - `FI INTERACTIONS row truth` beats frontmatter style preference.
    - frontmatter exact-match fields beat body-prose wording preference.
    - body-prose wording preference beats contract/flow vocabulary preference only inside interaction-spec body prose.
- In interaction spec body prose, prefer stable English label forms such as `request context`, `request message`, `context snapshot`, `turn history`, `chat session`, and `attachment` over raw snake_case keys.
- Do not propagate that body-prose English-label preference into FI `INTERACTIONS.summary` or FS frontmatter `summary`.
- Keep raw snake_case keys in category `contracts/*.toml` and `flows/*.md`; do not carry them into interaction spec prose unless the literal UI label itself uses that form.
- Exact state/status key formatting applies only to interaction spec body prose.
- Never apply that formatting inside `interaction_id`, filenames, markdown links, relative paths, frontmatter keys, or IA reference keys such as `related_region`.
- Use the contract/consistency workflow when creating or revising category-level `contracts/*.toml` and `flows/*.md`.
- Keep category contracts simple: prefer `contract` + `vocabulary` + `policy` + `status/ownership/transitions`, and avoid extra alias layers such as `object_terms` unless the user explicitly asks for them.
- Treat category flow docs as required companion artifacts for contract-driven FEATURE_SPEC work, not optional add-ons.
- Treat `검토 완료`, `reviewed`, or `human-reviewed` requests as human-review handoff actions only when the user explicitly names the target interaction spec path or `interaction_id`.

## Source of Truths

- `.agents/skills/voyager-product-owner/author/feature-spec/assets/TEMPLATE-feature-spec.md` (actual generation template)
- `.agents/skills/voyager-product-owner/author/feature-spec/assets/TEMPLATE-flow.md` (flow output template)
- `.agents/skills/voyager-product-owner/author/feature-spec/references/feature-spec-guide.md` (guide/reference)
- `.agents/skills/voyager-product-owner/author/feature-spec/references/flow-writing-guide.md` (flow authoring guide)
- `.agents/skills/voyager-product-owner/author/feature-spec/references/contract-writing-guide.md` (contract authoring guide)
- `.agents/skills/voyager-product-owner/author/feature-spec/references/contract-toml-spec.md` (contract TOML field spec)
- `.agents/skills/voyager-product-owner/author/feature-spec/references/contract-consistency-workflow.md` (contracts/flows workflow)
- `.agents/skills/voyager-product-owner/orchestrator/references/feature-spec-authoring-lifecycle.md`
- `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`

## Workflow

### 0) Confirm lifecycle stage first

- treat `FI` as the seed truth for `FS`
- do not start `FS` authoring while the required `feature`, `feature_id`, or `interaction_id` truth is still unresolved
- if the category uses shared vocabulary, write in this order:
    - `contract`
    - `flow`
    - `interaction spec`
- if missing or stale `structure_key` values block the spec set, request only the minimum IA sidecar update needed for the active bundle

Before writing or refactoring a spec body, use the asset files for fixed output shape and the reference files for the document contract and writing rules:

- `.agents/skills/voyager-product-owner/author/feature-spec/assets/TEMPLATE-feature-spec.md`
- `.agents/skills/voyager-product-owner/author/feature-spec/assets/TEMPLATE-flow.md` when editing `flows/*.md`
- `.agents/skills/voyager-product-owner/author/feature-spec/references/feature-spec-guide.md`
- `.agents/skills/voyager-product-owner/author/feature-spec/references/flow-writing-guide.md` when authoring or refactoring `flows/*.md`
- `.agents/skills/voyager-product-owner/author/feature-spec/references/contract-writing-guide.md` when deciding object/state vocabulary or transition scope
- `.agents/skills/voyager-product-owner/author/feature-spec/references/contract-toml-spec.md` when editing `contracts/*.toml`
- `.agents/skills/voyager-product-owner/author/feature-spec/references/contract-consistency-workflow.md` when updating the category-level contract + flow set

### 1) Generate or refine the shared FS contract

- update the category-level `contracts/*.toml` file first when the bundle depends on shared object, state, or transition vocabulary
- do not let interaction-spec wording become the source of truth for shared category vocabulary

### 2) Generate or refine the category flow

- update `flows/*.md` after the contract and before final interaction-spec refinement
- keep the flow doc aligned with the contract-owned objects, states, and branch boundaries

### 3) Generate a concrete draft from `interaction_id`

```bash
python3 .agents/skills/voyager-product-owner/author/feature-spec/scripts/generate_feature_spec.py <interaction_id>
```

For batch generation:

```bash
python3 .agents/skills/voyager-product-owner/author/feature-spec/scripts/generate_feature_spec.py \
  CDA-003-show_retrieval_results \
  FMW-001-open_new_file_manager_window \
  --output-dir PRODUCT/05_FEATURE_SPECS/_concrete-drafts \
  --overwrite
```

Behavior:

- reads matching row(s) from `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- resolves feature metadata from `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`
- emits a markdown draft whose metadata lives in YAML frontmatter
- writes to `PRODUCT/05_FEATURE_SPECS/<category>/<feature_id>-<slug>/<interaction_id>.md` unless `--output-dir` is provided

### 4) Lint existing specs

```bash
python3 .agents/skills/voyager-product-owner/author/feature-spec/scripts/lint_feature_spec.py PRODUCT/05_FEATURE_SPECS/.../*.md
```

Useful with strict mode:

```bash
python3 .agents/skills/voyager-product-owner/author/feature-spec/scripts/lint_feature_spec.py --strict PRODUCT/05_FEATURE_SPECS/cda/CDA-003-handle_retrieve_intent/*.md
```

### 5) Review and refine

- review generated sections and replace draft wording with concrete behavior text where needed
- keep the document aligned with the template and guide
- keep the category flow doc aligned with linked contracts and interaction specs
- clear the lifecycle's `FS local check` gate before handing the bundle to bundle validation
- commit as a focused docs change

### 6) Handle explicit human-review handoff for one interaction spec

Use this path when the user explicitly asks to mark a specific interaction spec as reviewed, such as:

- `<interaction spec path> 검토 완료로 넘겨줘`
- `<interaction_id> human-reviewed 처리해줘`

Also use this path when a specific target interaction spec already shows a one-file human-review signal relative to FI:

- the target FEATURE_SPEC no longer carries `<<AI>>` markers while the matching FI `summary` still does
- the target FEATURE_SPEC frontmatter `status` is no longer `아이디어` / `드래프트` while the matching FI row still is

Workflow:

1. Confirm the exact target interaction spec path or `interaction_id`.
2. Remove `<<AI>>` markers from the target interaction spec's human-readable frontmatter values and body prose in the same file.
3. If the target interaction spec frontmatter `status` is `아이디어` or `드래프트`, promote it to `기획 완료`.
4. Sync the matching `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv` row in the same pass:
    - remove `<<AI>>` from the corresponding long-text cell such as `summary`
    - if `status` is `아이디어` or `드래프트`, promote it to `기획 완료`
5. Re-run local validation for the touched spec and matching FI row before finishing.

Do not expand this handoff automatically to:

- sibling interaction specs
- the parent `FEATURES` row
- category `flows/*.md`
- category `contracts/*.toml`

## Guardrails

- Keep generation-time reminders in the skill or guide only; do not emit internal instruction comments into generated markdown files.
- Prefer product-facing wording over implementation-facing wording.
- Use the reference guide for frontmatter keys, fixed sections, section intent, shortcut notation, exact UI labels, interaction-link formatting, ambiguity avoidance, and `-` / `TBD` handling.
- Every contract-driven category should keep at least one `flows/*.md` doc that references the current `contracts/*.toml` and the interaction specs it covers.
- Keep generated prose Korean by default, but preserve literal product-facing UI copy in English when that is the settled label shown to users.
- Use strict lint as a review aid for unresolved `TBD` values and draft completeness.
- Do not rewrite frontmatter `summary` independently from the matching `INTERACTIONS` row.
- If you change a frontmatter `summary`, change the matching FI `INTERACTIONS` row in the same pass unless the user explicitly says not to sync FI.
- During explicit human-review handoff, edit only the named interaction spec and its matching FI interaction row unless the user asks for a wider sweep.
- Do not mass-edit unrelated spec files unless explicitly requested.

## Reference files

- `assets/` for fixed output templates and applied examples
- `references/` for guide/reference documents

## Scripts

- `scripts/generate_feature_spec.py`
    - `--output-dir` / `--overwrite` / `--template` / `--dry-run`
- `scripts/lint_feature_spec.py`
    - `--strict` for additional `TBD`-density warnings
    - exits non-zero on missing required sections or required metadata keys

## Notes

- Generation uses the skill's default asset template by default.
- Guide/reference material should explain how to use the template, not duplicate the template body.
- The linter still accepts legacy `## Metadata` markdown tables during transition, but YAML frontmatter is the preferred format.
