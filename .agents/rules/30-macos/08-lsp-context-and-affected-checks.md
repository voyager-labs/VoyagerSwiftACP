---
description: "Voyager macOS LSP context switching and affected verification command selection."
globs: "apps/macos/**"
---

# LSP Context and Affected Checks

## Applies when

- Touching Voyager macOS app, helper, XPC, host, package, or macOS test files.
- SourceKit-LSP, xcode-build-server, SweetPad, or affected verification confidence matters.

## Must

- Select the SourceKit-LSP context with `python3 scripts/dev/lsp_context.py` before relying on LSP diagnostics.
- Use `python3 scripts/dev/macos_checks.py` to derive affected package, app, helper, host, or XPC checks from paths.
- Treat LSP output as fast feedback only; use targeted build/test commands as the authoritative result.
- Report the exact context and commands used when verifying macOS changes.

## Must not

- Assume the current `buildServer.json` matches the files being edited.
- Use a broad all-dev scheme as a substitute for targeted package and Xcode checks.
- Claim package test coverage from an app scheme unless the package test target execution is visible in output.
- Hide `buildServer.json` or `build/` as durable project state; they remain local generated artifacts.

## Execution steps

1. For a known path, run `python3 scripts/dev/lsp_context.py --path <PATH>`.
2. For multiple changed paths, run `python3 scripts/dev/macos_checks.py --changed` or repeat `--path`.
3. If the selected LSP context differs from the current work area, regenerate it before diagnostics.
4. Run the planned checks from `macos_checks.py`, starting with package checks before downstream Xcode builds.
5. If checks are reduced or skipped, document why and state the confidence reduction.

## Verification

- `python3 scripts/dev/lsp_context.py --path <PATH> --dry-run --json` returns a scheme and project path.
- `python3 scripts/dev/macos_checks.py --path <PATH> --json` returns the affected check plan.
- Verification evidence includes both LSP context selection and targeted build/test command outcomes.
