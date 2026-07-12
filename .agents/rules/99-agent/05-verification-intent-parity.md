---
description: "Verification must match what the implementation intended to achieve, not just what is easy to check."
alwaysApply: true
schemaVersion: 2
---

# Verification Intent Parity

## Outcome

- Verify against the stated task intent, not against a generic checklist.
- If the intent is "refactor X to use Y", verify that X now uses Y (not just that tests still pass).
- If the intent is "add feature Z", verify Z works end-to-end, not just that it compiles.
- Map each intent item to at least one specific verification action.
- When intent has multiple parts, verify each part independently. Partial verification yields a degraded outcome (per `99-agent/06-outcome-classification.md`).
- Use the scope-based check matrix in `00-core/01-verification.md` for required checks, then add intent-specific checks on top.

## Default Actions

1. Read the task intent statement (from `99-agent/04-task-boundary-contract.md`).
2. List what "done" means for that intent specifically.
3. Run the scope-required checks from `00-core/01-verification.md`.
4. For each intent item, design and run a check that directly confirms that item.
5. If any intent item lacks a matching verification action, flag it as an unverified intent gap.
6. Classify the overall verification outcome using `99-agent/06-outcome-classification.md`.

## Decision Rules

## Stop Conditions

- Substitute "build passes" or "tests pass" for intent-specific verification.
- Verify only the happy path when the intent includes error handling or edge cases.
- Skip verification of non-code artifacts (configs, docs, schemas) when they are in scope.
- Treat passing tests as sufficient when the tests do not cover the changed behavior.
- Run only fast checks when the intent demands thorough validation.

## Verification

- Every stated intent item has at least one corresponding verification action.
- No intent item is verified only by proxy (e.g., "build passes" for a behavioral change).
- Any unverified intent gaps are explicitly documented in the evidence.
- Verification outcome matches the classification in `99-agent/06-outcome-classification.md`.
