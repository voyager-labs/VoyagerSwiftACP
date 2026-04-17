# PRODUCT AGENTS

## MISSION

This file is the operating harness for product-document work under `PRODUCT/`.
Treat this area as a product-ops lane, not a general writing lane.
The job is to route requests through the right agent and skill workflow, update the smallest necessary source of truth,
and close the loop with deterministic validation.

## SCOPE

This harness covers only these document layers:

- `PRODUCT/01_PRODUCT_THESIS/`
- `PRODUCT/02_USER_PERSONA/`
- `PRODUCT/03_INFORMATION_ARCHITECTURE/`
- `PRODUCT/04_FEATURE_INVENTORY/`
- `PRODUCT/05_FEATURE_SPECS/`

This harness does **not** cover:

- `PRODUCT/06_USE_CASES/`
- repo-tracked Linear issue draft directories under `PRODUCT/`

If a child directory has its own `AGENTS.md`, that deeper file wins for that subtree.

## PRIMARY SURFACES

| Surface        | Role                                | Main Entry                                     |
| -------------- | ----------------------------------- | ---------------------------------------------- |
| Product thesis | Why the change exists               | `PRODUCT/01_PRODUCT_THESIS/00_index.md`        |
| Persona        | Who the change is for               | `PRODUCT/02_USER_PERSONA/00_index.md`          |
| IA             | UI structure and stable UI keys     | `PRODUCT/03_INFORMATION_ARCHITECTURE/index.md` |
| FI             | Feature and interaction truth       | `PRODUCT/04_FEATURE_INVENTORY/index.md`        |
| FS             | Interaction-level behavior contract | `PRODUCT/05_FEATURE_SPECS/index.md`            |
| Subagents      | Reasoning/orchestration lane        | `.codex/agents/README.md`                      |

## HARNESS MODEL

Use two rails together:

1. Reasoning rail
    - Use project subagents to clarify, scope, author, and review.
    - Primary subagents: `product_interviewer`, `scope_reviewer`, `inventory_author`, `spec_author`, `bundle_reviewer`

2. Deterministic rail
    - Use repo skills and scripts for lookup, generation, auditing, and linting.
    - Primary skills: `voyager-feature-inventory-checker`, `voyager-feature-inventory-author`, `voyager-feature-spec-author`, `voyager-fi-ia-fs-consistency-checker`

Preferred pattern:

1. Use a subagent to decide what should change.
2. Use a skill or script to confirm the current truth and generate or validate the edit path.
3. Edit the minimal files.
4. Re-run the deterministic checker for the touched lane.

## DEFAULT LOOP

Run this loop unless the user gives a narrower instruction:

1. Clarify the product request.
    - Identify the problem, actor, desired outcome, and whether the request is a new capability or a refinement.
2. Scope the affected layer.
    - Decide whether the task belongs in thesis, persona, IA, FI, FS, or a small combination of them.
3. Check existing truth before writing.
    - Find existing `feature_id`, `interaction_id`, `structure_key`, and nearby bundle context first.
4. Update truth first.
    - Prefer `IA -> FI -> FS` order when multiple layers move together.
5. Audit the touched bundle.
    - Confirm references, generated files, and deterministic metadata still align.

## ROUTING PLAYBOOKS

### 1. Fuzzy product request

Use this when the user describes a need but not the exact feature or document layer.

1. `product_interviewer`
2. `scope_reviewer`
3. `voyager-feature-inventory-checker` if the request may overlap existing FI
4. `inventory_author` or `spec_author` depending on whether truth already exists
5. `bundle_reviewer` or `voyager-fi-ia-fs-consistency-checker` before finishing

### 2. Existing feature impact analysis

Use this when the user asks which feature or interaction is affected.

1. `voyager-feature-inventory-checker`
2. `scope_reviewer` if the impact spans more than FI
3. If one feature bundle is involved, prefer `voyager-fi-ia-fs-consistency-checker`
4. Only after the impact is clear, move into authoring

### 3. New FI authoring

Use this when the task is to add or refine `FEATURES` or `INTERACTIONS` rows.

1. `voyager-feature-inventory-checker` for duplicate and adjacency search
2. `inventory_author` for authoring intent and row shape
3. `voyager-feature-inventory-author` for the concrete TSV workflow
4. `voyager-feature-inventory-checker` again after editing

Do not start in FS for a feature that does not have settled FI truth.

### 4. FS drafting or refinement

Use this when the `interaction_id` already exists and the spec needs to be created or tightened.

1. Confirm the target `interaction_id` in FI first
2. `spec_author`
3. `voyager-feature-spec-author`
4. Run the feature spec linter on the touched files
5. If the change affects a broader bundle, finish with `voyager-fi-ia-fs-consistency-checker`

### 5. FI + IA + FS bundle audit

Use this when the user asks for consistency, mismatch review, drift cleanup, or stale spec sync.

1. `bundle_reviewer`
2. `voyager-fi-ia-fs-consistency-checker`
3. If the checker exposes missing truth, move backward into FI or FS authoring
4. Re-run the same checker after edits

### 6. IA-key change

Use this when a request may require a new `structure_key` or a changed UI hierarchy.

1. `scope_reviewer`
2. Inspect the existing IA hierarchy before adding keys
3. Use `voyager-feature-inventory-checker` to find impacted features and interactions
4. Edit IA only if the key or hierarchy change is genuinely needed
5. Propagate the new or changed key into FI and FS as required
6. Run `voyager-fi-ia-fs-consistency-checker` on the affected bundle

## WRITING MODE

- Write product documents in Korean by default.
    - Use English only for stable IDs, schema keys, filenames, code, or fixed technical artifacts.
- Keep the prose product-facing.
    - Prefer user behavior, system response, state transitions, and exception handling over implementation detail.
- Keep edits narrow.
    - One patch should usually represent one product decision or one coherent feature bundle.

## HARD STOPS

- Do not start from FEATURE_SPEC when the product problem or FI truth is still fuzzy.
- Do not create a new `feature_id`, `interaction_id`, or `structure_key` without first checking nearby existing truth.
- Do not update FS in a way that silently diverges from FI.
- Do not broad-clean unrelated bundles in the name of cleanup.
- Do not rename files or folders broadly unless the user explicitly asks for it and link fallout is understood.

## VALIDATION LADDER

Pick the smallest validation that matches the work:

1. FI row or feature lookup
    - Use `voyager-feature-inventory-checker`
2. New or changed FI rows
    - Re-run `voyager-feature-inventory-checker`
3. New or changed FS files
    - Run `voyager-feature-spec-author` lint workflow
4. Any bundle touching FI + IA + FS together
    - Run `voyager-fi-ia-fs-consistency-checker`

If the user asked for review only, stop after validation and report findings before writing.
