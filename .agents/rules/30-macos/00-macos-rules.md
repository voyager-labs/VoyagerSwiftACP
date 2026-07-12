---
description: "macOS runtime architecture and SwiftLint suppression contract."
globs: "apps/macos/**/*.swift"
schemaVersion: 2
---

# macOS Rules

## Outcome

- Keep the runtime architecture minimal: dependencies point downward, SwiftUI views render and send actions, and reducers or dependency clients own service/system work.
- Keep one canonical owner for each cross-layer concern, user-facing presentation policy, shared visual mapping, and multi-stage callback cleanup.
- The detailed FSD layer, segment, and public-boundary contract is `.agents/skills/voyager-dev/reviewer/boundary/references/layer-and-segment-rules.md`; this rule retains the runtime invariant that reverse dependencies are forbidden.
- This file is the canonical owner for SwiftLint suppression policy.

## Default Actions

1. Identify the owning FSD layer before editing state, copy, shared visual metadata, command routing, or system access; load the boundary reference when placement or a public surface changes.
2. Reuse existing dependency clients, reducers, and shared helpers; keep views as renderers and action senders, and move service/system work behind dependencies and reducers.
3. Route cross-feature or window-level commands through actions, delegate events, or dedicated handlers; preserve one owner for callback cleanup, resolved context, and visual state.
4. Load the focused contract when applicable: `.agents/rules/30-macos/02-tca-observation-lifecycle.md` for external observation, `.agents/rules/30-macos/03-voyager-app-workflow.md` for non-trivial Voyager work, `.agents/rules/30-macos/06-file-backed-storage-invariants.md` for file storage, `.agents/rules/30-macos/07-package-extraction-guardrails.md` for package extraction, and `.agents/rules/30-macos/09-entry-fixture-source.md` for entry fixtures.
5. Fix a SwiftLint violation in code. If a scoped fix would require an out-of-scope public or cross-layer change, report the rule name, file, line, and scope reason.

## Decision Rules

- A system event or service access that affects feature state belongs behind a dependency client and reducer; UI-only local presentation may remain in the view.
- Feature-to-feature dependencies require a declared `Package.swift` dependency and evidence that entity/shared promotion cannot remove the coupling.
- Keep presentation copy in feature/model-owned state, and keep shared icons or labels behind one helper or registry.
- A genuinely false-positive SwiftLint finding may use only `// swiftlint:disable:this <rule_name>` on the affected expression with a one-line rationale. Treat it as an evidence-backed exception, not a routine fix.
- Use `.agents/skills/voyager-dev/orchestrator/SKILL.md` for scaffold/orchestrator-style TCA work and `.agents/skills/code-tooling/SKILL.md` for code navigation, search, build, and diagnostics.

## Stop Conditions

- Do not introduce a reverse dependency, direct network/filesystem/system SDK access from a SwiftUI view, global singleton in place of an injectable client, parallel canonical type, or direct cross-feature state mutation.
- Do not place UI-facing policy in raw API/status clients or duplicate shared visual mapping.
- Do not add broad, file-level, block-level, `:next`, `all`, or configuration-based SwiftLint suppression. Do not silently suppress an out-of-scope violation.

## Verification

- Confirm no reverse import was added and that any feature-to-feature dependency is declared and justified.
- Confirm system/service work remains behind dependency clients and reducers, and each touched concept has one owner.
- Confirm callback cleanup, resolved context, and visual state do not have competing owners.
- Confirm no new SwiftLint suppression exists unless it is the narrow, rationale-bearing exception defined above.
