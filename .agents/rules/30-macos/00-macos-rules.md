---
description: "macOS runtime architecture and SwiftLint suppression contract."
globs: "apps/macos/**/*.swift"
schemaVersion: 2
---

# macOS Rules

## Outcome

- Reverse dependencies are forbidden; detailed FSD and public-boundary policy lives in `../../skills/voyager-dev/reviewer/review/references/layer-and-segment-rules.md`.
- SwiftUI views render and send actions; dependency clients and reducers own service and system work.
- This rule is the canonical owner for SwiftLint suppression policy.

## Default Actions

1. Fix SwiftLint findings in code; load the focused Voyager skill for lifecycle, storage, package, fixture, or app-workflow guidance.

## Decision Rules

- A genuine false positive may use only `// swiftlint:disable:this <rule_name>` on the affected expression with a one-line rationale.

## Stop Conditions

- Do not add reverse imports, direct network/filesystem/system SDK access from a SwiftUI view, global singletons in place of injectable clients, or direct cross-feature state mutation.
- Do not add broad, file-level, block-level, `:next`, `all`, or configuration-based SwiftLint suppression.

## Verification

- Confirm no reverse import or unjustified feature dependency was added.
- Confirm system/service work remains behind dependency clients and reducers, and any suppression is the narrow, rationale-bearing exception above.
