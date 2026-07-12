---
description: "Always load voyager-dev for Voyager macOS app, package, host, helper, and test work."
globs: "apps/macos/{Voyager,Packages,Hosts}/**"
schemaVersion: 2
---

# Voyager App Workflow

## Outcome

- Load the `voyager-dev` orchestrator entry at `.agents/skills/voyager-dev/orchestrator/SKILL.md` before planning or implementing changes in these paths.
- Use `voyager-dev` as the default companion workflow even for medium-sized refactors in app, package, host, helper, or test targets.
- Let `voyager-dev` classify the task shape internally and load the relevant playbooks before editing.
- Follow `voyager-dev` references when the change touches `State`, `Action`, reducer decomposition, external observation ownership, reuse discovery, or other Voyager-local architecture rules.

## Default Actions

1. Load the `voyager-dev` orchestrator entry at `.agents/skills/voyager-dev/orchestrator/SKILL.md` at task start.
2. Let `voyager-dev` classify the task shape and load the relevant playbooks.
3. Apply the selected playbooks, common development rules, TCA contract, and verification guidance from `voyager-dev`.

## Decision Rules

## Stop Conditions

- Skip `voyager-dev` for non-trivial Voyager macOS work in app, package, host, helper, XPC, or test paths.
- Add ad-hoc TCA/FSD structure changes in this path without checking the relevant `voyager-dev` guidance first.

## Verification

- Confirm the task explicitly loaded `voyager-dev` before implementation.
- Confirm the selected `voyager-dev` guidance matches the actual change shape.
