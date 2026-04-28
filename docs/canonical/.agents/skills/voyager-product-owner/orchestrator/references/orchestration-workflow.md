# Orchestration Workflow

Use this workflow by default for requests that land inside the Voyager `PRODUCT` harness. Explicit requests for delegation or subagents strengthen the expectation, but are not required for orchestration routing.

## Scope

This workflow writes and validates:

- `PRODUCT/03_INFORMATION_ARCHITECTURE/`
- `PRODUCT/04_FEATURE_INVENTORY/`
- `PRODUCT/05_FEATURE_SPECS/`
- repo-tracked Linear draft work only when the user explicitly asks

Reference-only inputs for scoping and validation:

- `PRODUCT/01_PRODUCT_THESIS/`
- `PRODUCT/02_USER_PERSONA/`

Use these directories to check actor, problem, and success-language alignment for IA/FI/FS work.
Do not route writes there unless the user explicitly asks.

Do not route into `PRODUCT/06_USE_CASES/` or other lanes unless the user explicitly asks.

## Boundary

`product-owner` is an orchestration entrypoint, not a container skill.

- Keep existing author/reviewer skills and project-scoped agents independent.
- Do not physically move `inventory-author`, `spec-author`, `bundle-reviewer`, or related skills under this skill directory.
- Treat them as stable delegate targets with their own trigger surfaces and evaluation histories.
- Use `feature-spec-authoring-lifecycle.md` as the source of truth for docs-first issue drafting, Phase 1 AI drafting, validation gates, and the Phase 2 handoff.

## Parent Responsibilities

The parent agent must:

- form a concise task brief first
- decide which lanes actually need delegation
- use `PRODUCT/01_PRODUCT_THESIS/` and `PRODUCT/02_USER_PERSONA/` as `reference_only` truth when checking whether IA/FI/FS changes still fit the product brief
- keep the write scope narrow
- integrate subagent outputs
- make final edits
- report the result to the user

Do not delegate the whole task blindly.

## Trigger Condition

Use this orchestration workflow by default whenever the task belongs to:

- `PRODUCT/03_INFORMATION_ARCHITECTURE/`
- `PRODUCT/04_FEATURE_INVENTORY/`
- `PRODUCT/05_FEATURE_SPECS/`

The parent may inspect `PRODUCT/01_PRODUCT_THESIS/` and `PRODUCT/02_USER_PERSONA/` as `reference_only` inputs when the user asks whether current IA/FI/FS docs still fit the top-level product truth.

Explicit requests for:

- subagents
- delegation
- parallel work
- worker/team style execution
- PRODUCT_OWNER orchestration

mean the parent should bias harder toward actual delegation instead of a local fallback.

## Agent Routing

Source of truth:

- `.codex/agents/README.md`
- `.codex/agents/*.toml`

### Reference alignment review

1. `scope_reviewer`
2. `bundle_reviewer` and/or `feature_spec_checker` depending on whether the request is bundle parity or FS contract/flow wording
3. keep thesis/persona read-only unless the user explicitly asks for a reference-doc rewrite

### Fuzzy product request

1. `product_interviewer`
2. `scope_reviewer`
3. `inventory_author` and/or `spec_author`
4. `bundle_reviewer` when more than one bundle layer is touched

### Comparative product or UX research

1. `product_researcher`
2. `scope_reviewer`
3. `inventory_author` and/or `spec_author`

### FI authoring or refinement

1. `scope_reviewer` when scope is unclear
2. `inventory_author`
3. `bundle_reviewer` when FI changes also affect IA or FS

### Docs-first feature-spec issue drafting

This lane is outside the default `PRODUCT` harness.

1. `scope_reviewer`
2. `feature_spec_issue_author`

Use this lane when the output should be a docs-first issue body that defines the expected IA/FI/FS touch set and the handoff into `Phase 1. AI Draft Authoring`.

### FS drafting or refinement

Default lifecycle:

1. `feature_inventory_checker`
2. `inventory_author` and `feature_inventory_author` when the FI seed truth is missing or stale
3. `information_architecture_author` when IA sidecar work such as `OBJECTS` or `WINDOW_STRUCTURE` support is needed
4. `spec_author`
5. `feature_spec_author`
6. `feature_spec_checker`
7. `bundle_reviewer` and `bundle_consistency_checker`
8. `spec_style_reviewer`

Use the fixed authoring order from `feature-spec-authoring-lifecycle.md`:

- `FI.feature_category -> FI.feature -> FI.interaction`
- `FS.contract -> FS.flow -> FS.interaction spec`

Do not claim `AI Draft Complete` until the lifecycle gates in that reference pass.

### FS tone or writing-style review

1. `spec_style_reviewer`
2. re-enter `spec_author` only if fixes are requested
3. rerun `spec_style_reviewer` when the user wants confirmation that the style pass is clean

### Consistency review only

1. `bundle_reviewer`

### Implementation issue drafting

1. `scope_reviewer`
2. `linear_issue_author`

## Delegation Pattern

### Step 1. Brief locally

Write a short local brief before delegating:

- user goal
- affected product area
- likely document layers
- open ambiguity
- expected final artifact

### Step 2. Delegate read-only classification first

If the task is fuzzy, spawn clarification/scope agents before authoring agents.

Do not send authoring agents into an unclear task if a scope pass would narrow it first.

### Step 3. Delegate authoring narrowly

When writing agents are used:

- assign concrete ownership
- define the target files or layers
- forbid speculative expansion
- tell the agent whether it is allowed to edit

### Step 4. Integrate in parent

The parent agent reconciles outputs and applies the final patch.

Do not let multiple subagents write the same file without a clear reason.

### Step 5. Validate

After integration, run only the smallest relevant validation pass.

Examples:

- FI/IA/FS bundle change: run the bundle checker
- contract/category change: run the category eval if available
- issue drafting only: no product-bundle checker unless the docs changed
- feature-spec authoring lifecycle: clear Gate 1, Gate 2, and Gate 3 before handing off to `Phase 2. Human Review`

## Fallback Rule

If the runtime cannot directly use project-scoped subagents, follow the same routing logic locally or via available generic delegation surfaces.

Do not pretend orchestration happened if it did not.

## Handoff Format

When reporting orchestration progress or outcomes, keep this structure:

1. `Brief`
2. `Chosen route`
3. `Delegated work`
4. `Parent integration`
5. `Validation`
