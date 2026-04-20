# Orchestration Workflow

Use this workflow when the user explicitly asks for PRODUCT_OWNER-style delegation, subagents, or parallel work on Voyager documentation.

## Scope

This workflow covers:

- `PRODUCT/01_PRODUCT_THESIS/`
- `PRODUCT/02_USER_PERSONA/`
- `PRODUCT/03_INFORMATION_ARCHITECTURE/`
- `PRODUCT/04_FEATURE_INVENTORY/`
- `PRODUCT/05_FEATURE_SPECS/`
- repo-tracked Linear draft work only when the user explicitly asks

Do not route into `PRODUCT/06_USE_CASES/` or other lanes unless the user explicitly asks.

## Boundary

`product-owner` is an orchestration entrypoint, not a container skill.

- Keep existing author/reviewer skills and project-scoped agents independent.
- Do not physically move `inventory-author`, `spec-author`, `bundle-reviewer`, or related skills under this skill directory.
- Treat them as stable delegate targets with their own trigger surfaces and evaluation histories.

## Parent Responsibilities

The parent agent must:

- form a concise task brief first
- decide which lanes actually need delegation
- keep the write scope narrow
- integrate subagent outputs
- make final edits
- report the result to the user

Do not delegate the whole task blindly.

## Trigger Condition

Use this orchestration workflow only when the user explicitly asks for one of these:

- subagents
- delegation
- parallel work
- worker/team style execution
- PRODUCT_OWNER orchestration

If the user does not ask for delegation, stay in single-agent mode.

## Agent Routing

Source of truth:

- `.codex/agents/README.md`
- `.codex/agents/*.toml`

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

### FS drafting or refinement

1. `scope_reviewer` when bundle impact is unclear
2. `spec_author`
3. `bundle_reviewer` when parity or contract review is needed

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
