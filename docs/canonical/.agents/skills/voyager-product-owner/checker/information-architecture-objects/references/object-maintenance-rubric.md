# IA OBJECTS Maintenance Rubric

Use this rubric when reviewing `PRODUCT/03_INFORMATION_ARCHITECTURE/OBJECTS/data.tsv`.

`OBJECTS` is the canonical noun layer for cross-contract product concepts.
The goal is not to maximize noun count. The goal is to keep a small, reusable, non-conflicting vocabulary.

## What To Review

### 1. Definition completeness

- `key` should be a stable snake_case noun
- `label_ko` should be short and readable in product language
- `summary` should explain the object as a reusable product concept, not as a schema field

### 2. Canonical noun vs local phrase

Promote a term into `OBJECTS` only when it is genuinely reused across contracts or specs.

Keep it out of `OBJECTS` when it is:

- a one-off relational phrase
- a temporary wording convenience inside one contract
- a description of implementation shape rather than a product concept

### 3. Duplicate vs scope split

When two rows feel close, classify them before editing:

- `merge candidate`
    - same product meaning
    - same Korean label or near-identical summary
    - one key is unused or only an accidental synonym
- `scope split`
    - one row is the base noun and the other is a request-scoped, session-scoped, or state-scoped derivative
    - both rows are actively referenced and each contract meaning would become less precise if merged
- `demote from OBJECTS`
    - the term exists only to explain one contract-local relation
    - the noun does not stand on its own outside that local flow

### 4. Category fit

Use category as an intent signal, not just a bucket:

- `Domain`: product-wide entities such as files, folders, collections, pages, providers
- `Conversation`: chat/session/request/response/turn intent flow nouns
- `State`: selected, active, snapshot, catalog, context-like state holders
- `Operation`: executable actions and commands
- `Rule`: scope, condition, filter, and other rule-like selectors

If a row's category and summary disagree, fix the disagreement before adding more related nouns.

### 5. Safe maintenance moves

Prefer these in order:

1. rewrite weak `summary`
2. tighten `label_ko`
3. keep both keys but sharpen scope boundaries
4. merge only when usage and meaning both collapse cleanly to one noun
5. delete only after confirming the key is not referenced by live contracts
