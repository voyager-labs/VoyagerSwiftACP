---
name: information-architecture-objects-checker
description: "Audit Voyager IA OBJECTS definitions in `PRODUCT/03_INFORMATION_ARCHITECTURE/OBJECTS/data.tsv`. Use whenever the user asks to review OBJECTS 정의 상태, object key 중복/겹침, 범위 분리, category 오배치, contract object 참조 정리, or 'IA objects 좀 정리해줘', especially when the work is about canonical object nouns rather than WINDOW_STRUCTURE or a full FI/IA/FS bundle."
---

# Voyager Information Architecture Objects Checker

Audit and maintain the canonical object noun layer in `IA > OBJECTS`.

In this repo:

- `IA` means `Information Architecture`
- this skill focuses on:
    - `PRODUCT/03_INFORMATION_ARCHITECTURE/OBJECTS/data.tsv`
    - `PRODUCT/03_INFORMATION_ARCHITECTURE/OBJECTS/schema.json`
    - `PRODUCT/05_FEATURE_SPECS/**/contracts/*.toml` object references

Use this skill when the user wants to:

- check whether `OBJECTS` rows are definition-complete
- review duplicate or overlapping object scope
- inspect whether base nouns and scoped derivatives are still clearly separated
- find contract object refs that are missing from `OBJECTS`
- clean up stale, weak, or unused object rows

Do not use this skill for:

- `WINDOW_STRUCTURE` or `MENUS` work
- whole-feature FI/IA/FS bundle audits
- drafting a brand new IA taxonomy from scratch without an existing object set

For those, use:

- `information-architecture-author`
- `fi-ia-fs-consistency-checker`

## Required References

Read these before reviewing or editing:

- `PRODUCT/03_INFORMATION_ARCHITECTURE/index.md`
- `.agents/skills/voyager-product-owner/author/information-architecture/references/objects-writing-guide.md`
- `references/object-maintenance-rubric.md`

## Workflow

1. Determine scope

- use the whole table when the user asks for broad maintenance
- use `--focus <term>` when the user asks about one family such as `context`, `request`, or `action`

2. Run the deterministic audit

Whole table:

```bash
python3 .agents/skills/voyager-product-owner/checker/information-architecture-objects/scripts/audit_objects.py
```

Focused family review:

```bash
python3 .agents/skills/voyager-product-owner/checker/information-architecture-objects/scripts/audit_objects.py --focus context
```

Structured output:

```bash
python3 .agents/skills/voyager-product-owner/checker/information-architecture-objects/scripts/audit_objects.py --json
```

3. Read findings by severity

- `FAIL`
    - broken key/category format
    - contract object refs missing from `OBJECTS`
- `WARN`
    - missing `label_ko` or `summary`
    - `TBD` left in definition cells
    - summary written too literally or with raw key leakage
    - unused object rows
    - likely duplicate labels/summaries
    - likely scope overlap that needs human review
- `INFO`
    - focused usage summaries
    - lower-risk family overlaps that are not clear duplicates yet

4. If the user asked for maintenance, edit narrowly

- keep existing keys stable unless contract usage proves the key should disappear
- prefer refining `label_ko` and `summary` before inventing a new key
- if two rows overlap, decide whether the problem is:
    - real duplication that should merge
    - parent/base noun vs scoped derivative that only needs sharper summaries
    - a local contract phrase that should not live in `OBJECTS`
- do not delete an object just because it is currently unreferenced without checking nearby contract/spec work in progress

5. Re-validate after edits

Always rerun:

```bash
python3 .agents/skills/voyager-product-owner/checker/information-architecture-objects/scripts/audit_objects.py
```

If you changed keys that category contracts already reference, rerun the affected contract checker too:

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/check_contract_consistency.py CBW
```

## Output Format

Report back in this order:

- `Findings`: `FAIL` first, then `WARN`
- `Scope Notes`: only when overlap/family review is the main issue
- `Validation`: commands run and whether they passed

If there are no `FAIL` or `WARN` items, say that `OBJECTS` is structurally clean and call out any remaining taxonomy judgment separately.

## Example Prompts

- `IA OBJECTS 전체 한번 점검해줘. 정의 빠진 거, 안 쓰는 거, 겹치는 거 있으면 알려줘`
- `context 계열 object들 범위가 겹치는지 봐줘. request_context까지 같이`
- `contract에서 object key는 늘었는데 OBJECTS가 못 따라간 것 같아. 누락/중복 체크해줘`
