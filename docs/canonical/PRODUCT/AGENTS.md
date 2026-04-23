# PRODUCT AGENTS

## Mission

Work under `PRODUCT/` always starts with the parent agent acting as the `product_owner` orchestrator.
This role is the single owner of scope decisions, routing, integration, final validation, and the final response.

The parent agent follows these rules:

- Always interpret the request inside the `PRODUCT` harness first.
- Even for small direct edits, let the parent agent decide scope and validation from the `product_owner` perspective.
- Default to delegated read/author/review routing for non-trivial PRODUCT work when the runtime allows subagents.
- Keep trivial single-file edits local only after the parent confirms that delegation adds little value.
- The parent agent integrates and validates all subagent output.

## Scope

This harness writes and validates only these layers by default:

- `PRODUCT/03_INFORMATION_ARCHITECTURE/`
- `PRODUCT/04_FEATURE_INVENTORY/`
- `PRODUCT/05_FEATURE_SPECS/`

Reference-only product truth inside the harness:

- `PRODUCT/01_PRODUCT_THESIS/`
- `PRODUCT/02_USER_PERSONA/`

Use these directories to check whether IA/FI/FS wording, actor assumptions, and product rules still follow the current top-level product truth.
Do not edit them unless the user explicitly asks for a thesis/persona revision.

Out of default scope:

- `PRODUCT/06_USE_CASES/`
- repo-tracked Linear draft directories under `PRODUCT/`

If a child directory has a deeper `AGENTS.md`, that file takes precedence for its subtree.

## Orchestration Rule

The default structure for `PRODUCT/` work is always:

1. The parent agent interprets the request as the `product_owner` orchestrator.
2. If needed, split read, author, and review work across parallel subagents.
3. Use deterministic skills or scripts to confirm current truth and validate outcomes.
4. The parent agent edits the minimum necessary files and closes validation.

In this harness, `product_owner` is not an optional helper skill. It is the default operating model.
Actual subagent spawning should happen by default for non-trivial PRODUCT work when the runtime permits it.
If higher-priority runtime policy blocks automatic spawning, keep the same routing logic locally and surface that limitation honestly.

For docs-first feature-spec work, the lifecycle source of truth is:

- `.agents/skills/voyager-product-owner/orchestrator/references/feature-spec-authoring-lifecycle.md`

## Canonical Names

Use the following canonical mapping between document-facing role names and actual execution surfaces.

| Role Name                         | Actual Name                       | Type     | Purpose                                    |
| --------------------------------- | --------------------------------- | -------- | ------------------------------------------ |
| `product_owner`                   | `product-owner`                   | skill    | Parent orchestration workflow              |
| `product_interviewer`             | `product_interviewer`             | subagent | Clarify fuzzy requests                     |
| `scope_reviewer`                  | `scope_reviewer`                  | subagent | Narrow document impact                     |
| `inventory_author`                | `inventory_author`                | subagent | Author FI and adjacent IA                  |
| `spec_author`                     | `spec_author`                     | subagent | Author FS, category flows, and adjacent IA |
| `bundle_reviewer`                 | `bundle_reviewer`                 | subagent | Audit one FI/IA/FS bundle                  |
| `spec_style_reviewer`             | `spec_style_reviewer`             | subagent | Review FS tone and writing style           |
| `product_researcher`              | `product_researcher`              | subagent | Research external products                 |
| `linear_issue_author`             | `linear_issue_author`             | subagent | Draft implementation issues                |
| `feature_spec_issue_author`       | `feature_spec_issue_author`       | subagent | Draft docs-first feature-spec issues       |
| `feature_inventory_checker`       | `feature-inventory-checker`       | skill    | FI lookup and impact workflow              |
| `feature_inventory_author`        | `feature-inventory-author`        | skill    | FI TSV authoring workflow                  |
| `information_architecture_author` | `information-architecture-author` | skill    | IA TSV authoring workflow                  |
| `feature_spec_author`             | `feature-spec-author`             | skill    | FS authoring and lint workflow             |
| `feature_spec_checker`            | `feature-spec-checker`            | skill    | FS contract/flow review                    |
| `bundle_consistency_checker`      | `fi-ia-fs-consistency-checker`    | skill    | Bundle consistency workflow                |
| `linear_issue_skill`              | `linear-issue-author`             | skill    | Linear issue drafting workflow             |

Rules:

- Use the left column for document-facing role names.
- Use the middle column only when you need to reference the actual execution surface.
- `product_owner` is the role name; the actual skill name is `product-owner`.
- Names like `feature_inventory_checker` are document aliases; the actual skill name is `feature-inventory-checker`.

## Routing

### 1. Small direct edit

If the target layer is clear and parallelism adds little value:

1. The parent agent scopes the task as `product_owner`
2. Use only the required deterministic skills
3. Let the parent agent edit directly
4. Run the smallest matching validation pass

### 1a. Reference alignment review

If the task is to check whether current IA/FI/FS docs still follow the reference-only thesis/persona:

1. `scope_reviewer`
2. `bundle_reviewer` and/or `feature_spec_checker` depending on whether the question is bundle parity or FS contract/flow wording
3. The parent agent reports drift first and edits IA/FI/FS only unless the user explicitly asks to revise the reference docs

### 2. Fuzzy request

If the request is fuzzy:

1. `product_interviewer`
2. `scope_reviewer`
3. `feature_inventory_checker` if needed
4. Route into the authoring lane

### 3. FI authoring

If the change centers on `FEATURES` or `INTERACTIONS`:

1. `feature_inventory_checker`
2. `scope_reviewer` if needed
3. `inventory_author`
4. `feature_inventory_author`
5. `feature_inventory_checker`

### 4. FS authoring

If the task is spec work for an existing `interaction_id`:

1. `feature_inventory_checker`
2. `inventory_author` and `feature_inventory_author` when the FI seed truth is missing or stale
3. `information_architecture_author` when IA sidecar work such as `OBJECTS` or `WINDOW_STRUCTURE` support is needed
4. `scope_reviewer` if needed
5. `spec_author`
6. `feature_spec_author`
7. `feature_spec_checker`
8. `bundle_reviewer` and `bundle_consistency_checker`
9. `spec_style_reviewer`

Apply this fixed authoring order:

1. `FI.feature_category`
2. `FI.feature`
3. `FI.interaction`
4. `FS.contract`
5. `FS.flow`
6. `FS.interaction spec`

Do not claim `AI Draft Complete` until the lifecycle gates have passed and the bundle is ready for `Phase 2. Human Review`.

### 4a. Docs-first feature-spec issue draft

If the task is to create or refine a `기능 스펙 정의` or `기능 스펙 정의 및 정리` issue:

1. `scope_reviewer`
2. `feature_spec_issue_author`

This lane is outside the default `PRODUCT` harness.
Its output is the docs-first issue body that defines the expected IA/FI/FS touch set and the handoff into `Phase 1. AI Draft Authoring`.

### 4b. FS contract/flow review

If the task is specifically about whether FEATURE_SPEC docs match current `contracts/*.toml` or `flows/*.md`:

1. `feature_spec_checker`
2. re-enter `spec_author` only if fixes are requested
3. rerun `feature_spec_checker`

### 4c. FS tone/style review

If the task is specifically about whether FEATURE_SPEC drafts are product-facing, consistent in tone, and free of obvious AI-draft wording:

1. `spec_style_reviewer`
2. re-enter `spec_author` only if fixes are requested
3. rerun `spec_style_reviewer`

### 5. Bundle audit

If the task is an FI/IA/FS consistency review:

1. `bundle_reviewer`
2. `bundle_consistency_checker`
3. Re-enter only the authoring lane that is actually required
4. Re-run the same checker

### 6. Comparative research

If the task is external product research:

1. `product_researcher`
2. `scope_reviewer` if needed
3. Keep the authoring lane as a separate follow-up step

### 7. Implementation issue draft

This is outside the default `PRODUCT` harness, but allowed when the user explicitly asks for it:

1. `scope_reviewer`
2. `linear_issue_author`
3. `linear_issue_skill`

## Parallelism

Use parallel subagents only when one of these applies:

- Clarification and scoping can proceed independently.
- FI authoring and bundle review are separable sidecars.
- Research and authoring preparation depend on different inputs.
- The task touches multiple PRODUCT layers and a read/author/review split will reduce integration risk.
- IA key maintenance can proceed as a sidecar while FI or FS work narrows the active bundle.

Rules for parallel execution:

- Give each subagent a narrow and independent responsibility.
- Do not assign overlapping file ownership to multiple subagents.
- Do not hand off the critical path from the parent agent.

## Writing Rules

- Write product documents in Korean by default.
- Preserve IDs, schema keys, filenames, code, and fixed artifacts as-is.
- Prioritize user behavior, state, exceptions, and product rules over implementation detail.
- Keep each change focused on one product decision or one feature bundle.

## Hard Stops

- Do not edit `PRODUCT/01_PRODUCT_THESIS/` or `PRODUCT/02_USER_PERSONA/` unless the user explicitly asks.
- When thesis/persona and IA/FI/FS drift, treat thesis/persona as `reference_only` truth by default and fix or flag the downstream docs first.
- Do not start from FS when FI truth is still unclear.
- Do not create a new `feature_id`, `interaction_id`, or `structure_key` before checking adjacent existing truth.
- Do not create FS content that diverges from FI.
- Do not mix unrelated bundle cleanup into the same patch.

## Validation

- Reference-only alignment review: compare touched IA/FI/FS docs against thesis/persona and report drift before editing the reference docs.
- FI lookup or row edit: `feature_inventory_checker`
- FS `contract -> flow -> interaction spec` gate: `feature_spec_checker`
- FI + IA + FS bundle gate: `bundle_consistency_checker`
- semantic contradiction review before `AI Draft Complete`: `bundle_reviewer`
- tone and writing-style review before `AI Draft Complete`: `spec_style_reviewer`

For review-only requests, report findings before making edits.
