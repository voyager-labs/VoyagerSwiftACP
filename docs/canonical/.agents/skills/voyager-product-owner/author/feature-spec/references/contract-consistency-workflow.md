# Contract & Consistency Workflow

Use this workflow when maintaining a contract-driven FEATURE_SPEC category.
In this repo's target state, a contract-driven category keeps both category-level `contracts/*.toml` files and at least one category-level `flows/*.md` doc.

## When To Use This Workflow

Use this workflow whenever:

- the same object/state vocabulary appears in multiple interaction specs
- one user flow spans multiple features
- an existing contract-driven category is being updated

Migration note:

- older categories may still be missing one or both artifacts
- new or actively edited contract-driven categories should create or update both the contract set and the canonical flow doc in the same pass

## Primary Goal

The primary goal is not to create "shared documents" in the abstract.

The primary goal is to create explicit contract artifacts that make these questions answerable:

- what is the primary object?
- which `OBJECTS.key` owns that object name?
- what are the exact allowed states?
- which interaction reads or writes which states?
- which transitions are allowed?
- which terms are forbidden because they would create drift?

`flow` docs are required companion artifacts in this consistency model.
They are not a substitute for the contract, but they are not optional support notes either.

## Document Types

### 1. Category contract

Path:

- `PRODUCT/05_FEATURE_SPECS/<category>/contracts/<name>.toml`

Use for:

- shared object-key selection against IA `OBJECTS`
- shared state vocabulary
- allowed and forbidden user-visible states
- ownership of reads/writes across interactions
- transition definitions that multiple interaction specs rely on

Rules:

- use TOML, not markdown
- keep it machine-readable first
- use exact object names from `PRODUCT/03_INFORMATION_ARCHITECTURE/OBJECTS/data.tsv` and exact state names
- use exact region names from `PRODUCT/03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/data.tsv` for `display_region`, `scope_region`, and `control_region`
- prefer keyed subtables when entries are naturally keyed by an identifier such as `interaction_id`
- do not put long explanatory prose here
- follow `contract-toml-spec.md` for field-level conventions
- keep the schema shallow unless the user explicitly needs more structure
    - prefer `contract`, `vocabulary`, `policy`, `user_visible_states`, `status`, `ownership`, and `transitions`
    - avoid `object_terms`, `relation_terms`, and similar alias registries unless synonym normalization is an explicit requirement
- only list true core object keys in `primary_object_key` and `secondary_object_keys`
    - if a term is a directional or relational concept such as `downstream_turn`, keep it in `vocabulary` only
    - if a term is a window, pane, sidebar, toolbar, field, list, or container already present in `WINDOW_STRUCTURE`, keep it in a region field only
- use `[vocabulary]` only for category-local terms that do not already belong in `OBJECTS`
- tolerate legacy `primary_object` and `secondary_objects` only as a migration bridge
- prefer product-native terms over invented execution abstractions
    - keep `request` and `response` when they already model the product correctly
    - use `turn` when the contract needs a unit that groups one `request` with its connected `response`
    - use `chat_session` instead of `conversation_session` for the session container in CBW docs unless the user explicitly requests otherwise
- if a repeated action or branch term appears in policy, define that term first in `[vocabulary]` and the linked flow doc unless the current schema already has a more precise home for it
- treat undefined repeated policy terms as contract debt even if the current checker does not emit a dedicated warning for them

Recommended structure:

```toml
[contract]
id = "cbw.request_lifecycle"
category = "CBW"
primary_object_key = "request"
secondary_object_keys = ["turn", "response"]

[policy]
single_processing_response_per_request = true

[user_visible_states]
allowed = ["processing", "completed", "failed", "cancelled"]
forbidden = ["queued", "cancelling"]

[state.processing]
description = "..."
entered_by = ["CBW-001-submit_chat_request"]
exits_to = ["completed", "failed", "cancelled"]

[ownership."CBW-001-submit_chat_request"]
reads = []
writes = ["processing"]

[transitions.processing_to_completed]
from = "processing"
to = "completed"
trigger = "CBW-003-stream_contextual_chat_response"
```

### 2. Category flow

Path:

- `PRODUCT/05_FEATURE_SPECS/<category>/flows/<name>.md`

Use for:

- cross-feature sequence
- happy path / cancel path / regenerate path
- overview diagrams
- feature handoff boundaries
- a single canonical narrative that ties the linked interaction specs back to the contract vocabulary

Rules:

- use markdown
- keep it human-readable
- follow `flow-writing-guide.md` and `../assets/TEMPLATE-flow.md`
- reference interaction specs and contract files directly
- use this doc to explain sequence, not to redefine the contract vocabulary
- keep `.md` as the default extension so prose, links, and fenced mermaid diagrams can live together in one file
- keep at least one canonical flow doc per contract-driven category

## How To Update Interaction Specs

When a category contract and flow set exists:

- keep the interaction spec focused on that interaction only
- reference the relevant `contracts/*.toml` and `flows/*.md`
- do not restate the full shared lifecycle in each interaction spec
- do not invent alternative object names or state names in prose

## Semantic Review Use

Use contract docs to narrow semantic review.

Do not claim that prose alone can be deterministically checked for object/state identity.

Instead:

- compare interaction prose against the declared contract
- flag drift when interaction prose uses different objects or states
- surface ambiguity explicitly if the contract is still missing

## Continuous Maintenance Workflow

When a category already has `contracts/*.toml`, keep the contract, flow docs, and interaction specs in sync with this loop:

1. Resolve term ownership before editing policy.
    - decide whether the repeated term belongs to `OBJECTS`, `[vocabulary]`, or the linked flow doc
    - check `WINDOW_STRUCTURE` before adding an `OBJECTS` row; UI surfaces and panes stay as region references
    - if the current contract shape has no dedicated action section, define repeated action or branch terms in `[vocabulary]` and the linked flow doc before using them in `[policy]`

1. Update the relevant contract file.
   Example:
    - add a new product-wide object to `OBJECTS` and then reference it from the contract
    - add a missing category-local term definition that policy or ownership depends on
    - add a new allowed state
    - remove a forbidden state
    - add or change an ownership binding
    - add or revise policy only after the referenced terms are already defined

1. Update the category flow doc.
    - reference the current contract files directly
    - link the interaction specs that own each step
    - keep happy-path and branch semantics aligned with the contract vocabulary
    - make the sequence consequence of repeated action or branch terms explicit instead of leaving policy keys to imply the meaning

1. Update the affected interaction specs.
    - use the exact object and state vocabulary declared in the contract
    - add or update contract references in the interaction specs
    - add or update flow references in the interaction specs
    - remove obsolete terms that the contract now forbids

1. Run the contract consistency checker.

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/check_contract_consistency.py CBW
```

1. Run the existing FI/IA/FS bundle checker for the affected features.

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/check_feature_bundle.py CBW-001
```

1. Resolve warnings before widening the rollout.
    - `spec.contract_reference_missing`: add the missing contract reference
    - `spec.state_term_missing`: replace vague wording with the declared state term or one of its allowed terms
    - `spec.object_term_missing`: name the correct object explicitly
    - `spec.forbidden_state_term_present`: remove or rewrite the forbidden term
    - undefined repeated policy term: treat as a manual review failure even if the current checker does not yet emit a dedicated code for it

1. If the user confirms human review of a long-text field, remove the `<<AI>>` marker from FI and FS in the same pass.
