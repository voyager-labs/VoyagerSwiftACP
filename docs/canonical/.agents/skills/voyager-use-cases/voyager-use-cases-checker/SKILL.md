---
name: voyager-use-cases-checker
description: Deterministic linting for Voyager 05_USE_CASES markdown docs. Validate PREV/NEXT navigation and verify Happy Path table references for Invoked Interaction (<FEATURE_ID>-<slug>) and UI Surface keys against INTERACTIONS and WINDOW_STRUCTURE SSOT TSVs.
---

# Voyager Use Cases Checker

Deterministically validate `05_USE_CASES/*.md` so use-case docs stay consistent with SSOT tables and navigation.

## Quick Start

Check all use cases referenced by `05_USE_CASES/index.md`:

```bash
python3 .agents/skills/voyager-use-cases/voyager-use-cases-checker/scripts/check_use_cases.py
```

Check a single file:

```bash
python3 .agents/skills/voyager-use-cases/voyager-use-cases-checker/scripts/check_use_cases.py --file 05_USE_CASES/uc01-디렉토리를_브라우징하며_필요한_엔트리_열기.md
```

Treat unknown IDs/keys as errors (useful for tightening quality over time):

```bash
python3 .agents/skills/voyager-use-cases/voyager-use-cases-checker/scripts/check_use_cases.py --strict
```

CI-style: fail on warnings too:

```bash
python3 .agents/skills/voyager-use-cases/voyager-use-cases-checker/scripts/check_use_cases.py --fail-on-warn
```

## What This Checks

- Navigation in each UC doc
  - `USE_CASES` link exists
  - `PREV:` / `NEXT:` targets exist and match the order in `05_USE_CASES/index.md`
- Happy Path table references
  - Finds Markdown tables that include `Invoked Interaction` and `UI Surface` columns
  - Extracts interaction_id-like tokens from the `Invoked Interaction` column and verifies they exist in `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv` (`interaction_id`)
  - Extracts key-like tokens from the `UI Surface` column and verifies they exist in `03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/data.tsv` (`structure_key`)

## Sources Of Truth (Repo)

- `05_USE_CASES/index.md`
- `05_USE_CASES/*.md`
- `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- `03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/data.tsv`

## Notes

- Some Markdown cells escape underscores as `\_`; the checker normalizes this.
- `UI Surface` may temporarily be human-readable text; the checker only flags values that look like a `structure_key` but do not exist.
