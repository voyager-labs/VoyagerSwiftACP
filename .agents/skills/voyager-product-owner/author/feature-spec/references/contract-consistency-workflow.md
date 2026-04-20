# Contract & Consistency Workflow

Use this workflow when an interaction spec alone is no longer enough to keep object vocabulary, state vocabulary, and cross-feature consistency stable.

## When To Use This Workflow

Use this workflow when either condition is true:

- the same object/state vocabulary appears in multiple interaction specs
- one user flow spans multiple features and needs a single consistency source instead of repeated prose

Do not force this structure onto isolated interactions that do not share vocabulary or flow.

## Primary Goal

The primary goal is not to create "shared documents" in the abstract.

The primary goal is to create explicit contract artifacts that make these questions answerable:

- what is the primary object?
- which `OBJECTS.key` owns that object name?
- what are the exact allowed states?
- which interaction reads or writes which states?
- which transitions are allowed?
- which terms are forbidden because they would create drift?

`flow` docs exist to support this consistency model, not as the primary artifact.

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
- prefer keyed subtables when entries are naturally keyed by an identifier such as `interaction_id`
- do not put long explanatory prose here
- follow `contract-toml-spec.md` for field-level conventions
- keep the schema shallow unless the user explicitly needs more structure
    - prefer `contract`, `vocabulary`, `policy`, `user_visible_states`, `status`, `ownership`, and `transitions`
    - avoid `object_terms`, `relation_terms`, and similar alias registries unless synonym normalization is an explicit requirement
- only list true core object keys in `primary_object_key` and `secondary_object_keys`
    - if a term is a directional or relational concept such as `downstream_turn`, keep it in `vocabulary` only
- use `[vocabulary]` only for category-local terms that do not already belong in `OBJECTS`
- tolerate legacy `primary_object` and `secondary_objects` only as a migration bridge
- prefer product-native terms over invented execution abstractions
    - keep `request` and `response` when they already model the product correctly
    - use `turn` when the contract needs a unit that groups one `request` with its connected `response`
    - use `chat_session` instead of `conversation_session` for the session container in CBW docs unless the user explicitly requests otherwise

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

Rules:

- use markdown
- keep it human-readable
- reference interaction specs and contract files directly
- use this doc to explain sequence, not to redefine the contract vocabulary
- keep `.md` as the default extension so prose, links, and fenced mermaid diagrams can live together in one file

## How To Update Interaction Specs

When a category contract or flow exists:

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

When a category already has `contracts/*.toml`, keep the contract and interaction specs in sync with this loop:

1. Update the relevant contract file first.
   Example:
   - add a new product-wide object to `OBJECTS` and then reference it from the contract
   - add a new allowed state
   - remove a forbidden state
   - add or change an ownership binding

2. Update the affected interaction specs.
   - use the exact object and state vocabulary declared in the contract
   - add or update contract references in the interaction specs
   - remove obsolete terms that the contract now forbids

3. Run the contract consistency checker.

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/check_contract_consistency.py CBW
```

4. Run the existing FI/IA/FS bundle checker for the affected features.

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/check_feature_bundle.py CBW-001
```

5. Resolve warnings before widening the rollout.
   - `spec.contract_reference_missing`: add the missing contract reference
   - `spec.state_term_missing`: replace vague wording with the declared state term or one of its allowed terms
   - `spec.object_term_missing`: name the correct object explicitly
   - `spec.forbidden_state_term_present`: remove or rewrite the forbidden term

6. If the user confirms human review of a long-text field, remove the `<<AI>>` marker from FI and FS in the same pass.
