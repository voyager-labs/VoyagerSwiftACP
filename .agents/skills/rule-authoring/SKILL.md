---
name: rule-authoring
description: Guides authoring and placement of agent rules. Use when creating or updating .agents/rules files.
---

# Rule Authoring Governance

## Instructions

Use this skill for `.agents/rules/**` authoring and placement only. It does not replace `skill-author`, which governs authoring skills under `.agents/skills/**`.

## Outcome

- A rule is a concise, English, imperative operational contract for one topic, with observable invariants and no product narrative or long tutorial.
- New and updated rules conform to this schema unless a documented exception is approved in the same PR.
- Keep files concise, with a target of 150 lines or fewer.
- Preserve every user-visible safety, approval, scope, secret, destructive-action, and verification invariant during migration.

## Default Actions

1. Search for related rules before adding a new file, and use an existing rule when it can represent the policy.
2. Keep policy with its canonical owner. Link to that owner rather than duplicate policy text.
3. Update references when a rule is moved or renamed.
4. Put normal authoring behavior and ordered safe actions in this section. Keep branches, fallback selection, and exceptions out of it.

## Decision Rules

- Use exactly one applicability mechanism in frontmatter: `alwaysApply: true` for cross-task rules, or `globs` for path-scoped rules. Never set both.
- Use `alwaysApply` only when the rule applies regardless of the changed path. Use `globs` when applicability is path-specific.
- Put applicability selection, owner selection, fallbacks, and exception handling in this section.
- Map legacy normal-path obligations to Outcome or Default Actions. Map legacy conditional behavior and `Execution steps` to Decision Rules when it is a branch or fallback.
- Preserve semantic strength: a legacy requirement remains a requirement, and a legacy prohibition remains a prohibition. A migration that weakens an obligation is blocked.
- Mechanically enforceable prohibitions may move to a validator, hook, or CI only when the user-visible invariant remains in Outcome and replacement evidence exists.

## Stop Conditions

- Stop before adding or updating a rule that cannot meet this schema, preserve its existing safety boundary, or identify its canonical owner. Record the exception and reason in the same PR.
- Do not duplicate a policy that a canonical rule already owns.
- Do not place long tutorials or product narratives in rule files.
- Put approval requirements, destructive-action limits, secret-handling boundaries, scope-expansion boundaries, and other hard prohibitions in this section.
- Map legacy `Must not` obligations and legacy boundaries here without making them permissive.

## Verification

- Verify that references are live, statements do not conflict, the applicable frontmatter mechanism is singular, and the five v2 sections occur once in the required order.
- Verify that a new rule was added only when an existing rule cannot represent the policy.
- Record evidence for the required checks in the task or PR.
- Use the following traceability table when migrating a legacy rule. Review every row before treating the migration as complete.

| Legacy source   | Legacy obligation                                                              | v2 destination                                                          | Preserved requirement                                                                                     |
| --------------- | ------------------------------------------------------------------------------ | ----------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Applies when    | Applicability is stated as a body heading when present                         | Decision Rules                                                          | Select exactly one frontmatter mechanism, `alwaysApply` or `globs`, and choose it by scope.               |
| Must            | Keep rules in English and imperative voice                                     | Outcome                                                                 | The operational-contract language and voice remain mandatory.                                             |
| Must            | Use the legacy `Must`, `Must not`, `Execution steps`, and `Verification` order | Outcome, Default Actions, Decision Rules, Stop Conditions, Verification | The legacy format is replaced by the ordered v2 schema, with each legacy obligation mapped by this table. |
| Must            | Keep one topic per file                                                        | Outcome                                                                 | One-topic scope remains mandatory.                                                                        |
| Must            | Prefer links over duplicated policy text                                       | Default Actions                                                         | Authors link to the canonical owner instead of copying policy.                                            |
| Must            | Keep files concise, target 150 lines or fewer                                  | Outcome                                                                 | The 150-line target remains.                                                                              |
| Must            | Treat the format as mandatory for new or updated rules                         | Outcome                                                                 | v2 conformance is mandatory unless an exception is documented.                                            |
| Must            | Document a format exception and reason in the same PR                          | Stop Conditions                                                         | Work stops until the exception and its reason are recorded in the same PR.                                |
| Must not        | Do not store long tutorials or product narratives in rules                     | Stop Conditions                                                         | This prohibition remains absolute.                                                                        |
| Must not        | Do not duplicate policy across files                                           | Stop Conditions                                                         | This prohibition remains absolute.                                                                        |
| Execution steps | Search related rules before adding one                                         | Default Actions                                                         | Search is the first normal authoring action.                                                              |
| Execution steps | Update references when moving or renaming                                      | Default Actions                                                         | Reference updates remain required.                                                                        |
| Execution steps | Verify no dead links or contradictory statements                               | Verification                                                            | Both checks remain required and evidenced.                                                                |
| Verification    | Changed rules contain `Must` and `Must not`                                    | Outcome, Stop Conditions                                                | v2 requires Outcome and Stop Conditions instead of the legacy headings.                                   |
| Verification    | Changed rules contain actionable `Execution steps`                             | Default Actions, Decision Rules                                         | v2 requires normal actions and branches instead of the legacy heading.                                    |
| Verification    | Changed rules contain a verifiable `Verification` check                        | Verification                                                            | At least one executable, evidenced check remains required.                                                |
| Verification    | No duplicate policy text when a canonical rule exists                          | Default Actions, Stop Conditions                                        | Canonical linking is required and duplication is prohibited.                                              |
| Verification    | Add a new rule only when existing rules cannot represent the policy            | Verification                                                            | Necessity for a new rule remains a required check.                                                        |
| Quality gate    | A rule change is specific, testable, and non-duplicative                       | Outcome, Verification                                                   | The completed change must satisfy all three properties.                                                   |

## Placement Taxonomy

| Artifact kind                      | Target path                            | Examples                                                                                                         |
| ---------------------------------- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Cross-cutting deterministic rules  | `.agents/rules/00-core/`               | `00-execution-contract.md`, `02-verification.md`                                                                 |
| Platform-specific execution checks | Owning platform skill references       | `voyager-dev/orchestrator/references/voyager-app-workflow.md`, `code-tooling/references/test-plan-visibility.md` |
| All new skills                     | `.agents/skills/<kebab-case>/SKILL.md` | `pr-review`, `compound-review`                                                                                   |
| Agent-harness infrastructure rules | `.agents/rules/99-agent/`              | `00-scope-diff-isolation.md`, `01-task-boundary-contract.md`                                                     |

1. Classify the artifact as cross-cutting, platform-specific, skill, or harness infrastructure.
2. Select the target directory from the placement taxonomy and list its existing rules before assigning the next sequential number.
3. Keep skill directory names in `kebab-case` and keep each rule file to 150 lines or fewer.

- Place cross-cutting rules, which apply regardless of platform, in `00-core/`.
- Place rules applying only to `apps/macos/**` or `apps/backend/**` in the matching domain directory.
- Do not create `.agents/rules/voyager/` or a subdirectory that duplicates the `30-macos/` domain split.
- Do not place cross-cutting rules in `20-backend/` or `30-macos/`, or platform-specific rules in `00-core/` or `99-agent/`.
