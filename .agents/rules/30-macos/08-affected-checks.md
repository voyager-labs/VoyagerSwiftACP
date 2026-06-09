---
description: "Voyager macOS affected verification command selection."
globs: "apps/macos/**"
---

# Affected Checks

## Applies when

- Touching Voyager macOS app, helper, XPC, host, package, or macOS test files.
- Affected verification confidence matters.

## Must

- Use `python3 scripts/dev/macos_checks.py` to derive affected package, app, helper, host, or XPC checks from paths.
- Treat CodeGraph/grep/ast-grep output as fast feedback only; use targeted build/test commands as the authoritative result.
- Report the exact context and commands used when verifying macOS changes.

## Must not

- Use a broad all-dev scheme as a substitute for targeted package and Xcode checks.
- Claim package test coverage from an app scheme unless the package test target execution is visible in output.

## Execution steps

1. For a known path, run `python3 scripts/dev/macos_checks.py --path <PATH>`.
2. For multiple changed paths, run `python3 scripts/dev/macos_checks.py --changed` or repeat `--path`.
3. Run the planned checks from `macos_checks.py`, starting with package checks before downstream Xcode builds.
4. If checks are reduced or skipped, document why and state the confidence reduction.

## Verification

- `python3 scripts/dev/macos_checks.py --path <PATH> --json` returns the affected check plan.
- Verification evidence includes affected check plan and targeted build/test command outcomes.
