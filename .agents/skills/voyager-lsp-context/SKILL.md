---
name: voyager-lsp-context
description: Selects Voyager macOS SourceKit-LSP contexts and affected verification checks for app, helper, XPC, host, package, and test changes. Use when working on Voyager macOS files, SourceKit-LSP, xcode-build-server, SweetPad, buildServer.json, or when deciding which package/Xcode checks to run.
compatibility: opencode
---

# Voyager LSP Context

## When to use this skill

- You touch files under `apps/macos/Voyager/**`, `apps/macos/Packages/**`, or `apps/macos/Hosts/**`.
- LSP diagnostics, `buildServer.json`, SweetPad, scheme switching, or affected verification are relevant.
- You need agent-friendly commands for package tests, app/helper/host builds, or XPC checks.

## Instructions

1. Load `.agents/rules/30-macos/08-lsp-context-and-affected-checks.md` and the normal Voyager macOS rules.
2. Pick the LSP context with one of:
    - `python3 scripts/dev/lsp_context.py --path <PATH>`
    - `python3 scripts/dev/lsp_context.py --scope app|helper|onboarding`
3. Plan verification with one of:
    - `python3 scripts/dev/macos_checks.py --path <PATH>`
    - `python3 scripts/dev/macos_checks.py --changed`
    - add `--json` when another agent or script needs machine-readable output.
4. Run only the relevant planned checks, broadening from package checks to downstream Xcode builds when shared APIs or consumers changed.
5. Report the selected LSP scheme/project and exact checks run. Say explicitly when LSP was not authoritative.

## Context mapping

- App and most package work: `Voyager-Dev` via `apps/macos/Voyager/Voyager.xcodeproj`.
- Helper work: `VoyagerHelper-Dev` via `apps/macos/Voyager/Voyager.xcodeproj`.
- Onboarding host and onboarding package work: `OnboardingHost-Dev` via `apps/macos/Hosts/OnboardingHost/OnboardingHost.xcodeproj`.
- `FilterSearchXPC`: use targeted Xcode target build because the repo has no dedicated shared XPC scheme.

## Common mistakes

- Trusting whatever `buildServer.json` happens to contain from a previous task.
- Treating LSP green as proof that package tests, host builds, or helper tests passed.
- Running the whole app test suite before a fast package-level check.
- Forgetting that package source targets may be covered by an app scheme while package test targets still need explicit execution.

## Examples

```bash
python3 scripts/dev/lsp_context.py --path apps/macos/Packages/04_Features/Composer/Sources
python3 scripts/dev/macos_checks.py --path apps/macos/Packages/04_Features/Composer --json
python3 scripts/dev/lsp_context.py --scope helper
python3 scripts/dev/macos_checks.py --changed --run
```
