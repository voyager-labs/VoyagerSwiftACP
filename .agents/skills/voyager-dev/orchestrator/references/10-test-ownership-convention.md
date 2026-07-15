---
description: "Product behavior tests must live in spec-owner suites."
---

# Test Ownership Convention

## Must

- Place product behavior tests in the spec-owner test suite named `<SpecID><PascalCaseTitle>Tests.swift`.
- Organize interaction AC tests as `// MARK: - <spec-id>-<interaction_id>` sections inside the owning suite.
- Load the `spec-test-authoring` skill before creating or restructuring test files.
- Place fixtures, recorders, and support code under `Support/`.

## Must not

- Create standalone ad-hoc product behavior test files outside spec-owner suites.
- Use a `FeatureTests` suffix on new spec AC suites.
- Add product behavior assertions in technical or contract test suites that do not own the spec.

## Execution steps

1. Identify the spec ID for the behavior being tested.
2. Check if an owning suite already exists.
3. If yes, add a `// MARK:` section for the new interaction.
4. If no, create the suite using the `spec-test-authoring` skill.
5. Keep all support infrastructure under `Support/`.

## Verification

- New test file names match `<SpecID>...Tests.swift` (no `FeatureTests`).
- New test methods are under a `// MARK:` section with a valid spec ID.
- No standalone product behavior test files exist outside spec suites.
