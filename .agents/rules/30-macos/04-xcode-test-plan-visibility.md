---
globs: apps/macos/**/*.swift
description: "Xcode/SPM test-plan visibility safeguard: ensure intended test targets are actually executed."
---

# Xcode/SPM Test-Plan Visibility

## Applies when

- Running tests for a scheme that includes SPM package test targets.
- Acceptance criteria depend on SPM package test results (not just project-level test targets).
- Working in any Xcode workspace/project that references SPM packages with test targets.

## Must

- Before relying on test output, verify that the active test plan includes all intended test targets — not just project-level targets.
- Treat "build succeeded" as distinct from "all intended tests executed and passed".
- When acceptance criteria require SPM package test execution, prefer an explicit `.xcctestplan` file over the auto-created test plan.
- If CLI test execution cannot reach SPM package test targets (e.g., auto-created test plan excludes them), record the limitation explicitly in evidence before claiming test coverage.

## Must not

- Assume that a passing test run executed all SPM package test targets.
- Treat auto-created test plans (`shouldAutocreateTestPlan=YES`) as equivalent to explicit `.xcctestplan` files when package test coverage is required.
- Generalize this Xcode/CLI-specific behavior into cross-language or cross-platform rules (e.g., `00-core`).

## Execution steps

### MCP-first path

When XcodeBuildMCP is available:

1. Identify which test targets the task intends to cover (project targets + SPM package targets).
2. Use `test_sim` or build/run tools to execute tests.
3. Inspect the test output for target names.
4. Compare intended targets against executed targets.
5. If parity is achieved, proceed and record the result.
6. If SPM package targets are missing:
   a. Check whether an explicit `.xcctestplan` exists for the scheme.
   b. If not, create or update one to include the missing package test targets.
   c. If CLI execution of package tests is not feasible, document the limitation in evidence.

### CLI fallback path

When XcodeBuildMCP is not available, use raw CLI:

```bash
# Option A: List test targets in the auto-created or explicit test plan
xcodebuild test -scheme <SCHEME> -project <PROJECT> \
  -showTestPlans 2>/dev/null | grep -E 'Test plan|Test target'

# Option B: Extract executed test identifiers from result bundle
xcrun xcresulttool get test-results summary \
  --path <PATH_TO_XCRESULT> 2>/dev/null | grep -E 'Test target|Tests'

# Option C: Quick parity check — run tests and inspect output for target names
xcodebuild test -scheme <SCHEME> -project <PROJECT> \
  -resultBundlePath /tmp/test-result 2>&1 | grep -E 'Test suite .*(started|passed)'
```

## Verification

- **PASS**: Every intended test target (project + SPM package) appears in the test output.
- **FAIL**: Any intended test target is absent from the output.
- On FAIL, create or fix the `.xcctestplan` before proceeding, or record the limitation in evidence.

## Example (illustrative only)

A scheme referencing SPM packages under `apps/macos/Packages/**` may have an auto-created test plan that only includes `VoyagerTests` but skips package targets such as `VoyagerPagesSettingsTests` or `VoyagerEntitiesAiTests`. The verification command above would surface this gap as a FAIL.
