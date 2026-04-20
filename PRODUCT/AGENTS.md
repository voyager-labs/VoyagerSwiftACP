# PRODUCT AGENTS

## Mission

Work under `PRODUCT/` always starts with the parent agent acting as the `product_owner` orchestrator.
This role is the single owner of scope decisions, routing, integration, final validation, and the final response.

The parent agent follows these rules:

- Always interpret the request inside the `PRODUCT` harness first.
- Even for small direct edits, let the parent agent decide scope and validation from the `product_owner` perspective.
- Spawn subagents only when there is clear value in parallelism.
- The parent agent integrates and validates all subagent output.

## Scope

This harness covers only these layers by default:

- `PRODUCT/01_PRODUCT_THESIS/`
- `PRODUCT/02_USER_PERSONA/`
- `PRODUCT/03_INFORMATION_ARCHITECTURE/`
- `PRODUCT/04_FEATURE_INVENTORY/`
- `PRODUCT/05_FEATURE_SPECS/`

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
Actual subagent spawning is still conditional and should happen only when needed.

## Canonical Names

Use the following canonical mapping between document-facing role names and actual execution surfaces.

| Role Name                    | Actual Name                    | Type     | Purpose                        |
| ---------------------------- | ------------------------------ | -------- | ------------------------------ |
| `product_owner`              | `product-owner`                | skill    | Parent orchestration workflow  |
| `product_interviewer`        | `product_interviewer`          | subagent | Clarify fuzzy requests         |
| `scope_reviewer`             | `scope_reviewer`               | subagent | Narrow document impact         |
| `inventory_author`           | `inventory_author`             | subagent | Author FI and adjacent IA      |
| `spec_author`                | `spec_author`                  | subagent | Author FS and adjacent IA      |
| `bundle_reviewer`            | `bundle_reviewer`              | subagent | Audit one FI/IA/FS bundle      |
| `product_researcher`         | `product_researcher`           | subagent | Research external products     |
| `linear_issue_author`        | `linear_issue_author`          | subagent | Draft implementation issues    |
| `feature_inventory_checker`  | `feature-inventory-checker`    | skill    | FI lookup and impact workflow  |
| `feature_inventory_author`   | `feature-inventory-author`     | skill    | FI TSV authoring workflow      |
| `feature_spec_author`        | `feature-spec-author`          | skill    | FS authoring and lint workflow |
| `bundle_consistency_checker` | `fi-ia-fs-consistency-checker` | skill    | Bundle consistency workflow    |
| `linear_issue_skill`         | `linear-issue-author`          | skill    | Linear issue drafting workflow |

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
2. `scope_reviewer` if needed
3. `spec_author`
4. `feature_spec_author`
5. `bundle_consistency_checker` if needed

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

- Do not start from FS when FI truth is still unclear.
- Do not create a new `feature_id`, `interaction_id`, or `structure_key` before checking adjacent existing truth.
- Do not create FS content that diverges from FI.
- Do not mix unrelated bundle cleanup into the same patch.

## Validation

- FI lookup or row edit: `feature_inventory_checker`
- FS authoring or refinement: `feature_spec_author` lint workflow
- FI + IA + FS changes together: `bundle_consistency_checker`

For review-only requests, report findings before making edits.
