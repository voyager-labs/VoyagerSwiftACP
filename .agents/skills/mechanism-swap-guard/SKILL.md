---
name: mechanism-swap-guard
description: "Guards review-driven fixes against replacing proven working mechanisms (file copy/move, parsing, locking, streaming primitives) when adding detection or a guard on top would suffice. Use when implementing reviewer or bot findings, security hardening (TOCTOU, symlink swap, race, memory safety), P1/P2 fixes whose suggested direction is 'replace X with Y', or any fix touching a mechanism that already has passing tests and production history. Triggers on: security hardening, replace moveItem/renameat/fcopyfile/copyfile callback, reviewer suggested replacement, regression after security fix, mechanism substitution, EXDEV cross-volume fallback, chunked copy rewrite."
---

# Mechanism Swap Guard

Core rule: **prefer keeping a proven working mechanism and add detection or a guard when that closes the review finding.** If the mechanism is itself the confirmed root cause, or no guard can close the finding, replacement is allowed only with the capability-parity checklist and RED-first evidence below.

## When to use this skill

- A reviewer/bot finding suggests replacing a working primitive (e.g. `fcopyfile` → manual chunk loop, `moveItem` → `renameat`)
- Security hardening work: TOCTOU, symlink substitution, race windows, fd pinning
- The mechanism being touched has passing tests or production history
- You are inside a review-feedback cycle (fix → verify → push → reply → resolve) with a speed constraint

## When NOT to use this skill

- Greenfield code with no proven mechanism to preserve
- A dedicated plan with its own capability-parity checklist and RED-first TDD cycle owns the rewrite

## Instructions

1. Classify the finding against the ladder below and stop at the first rung that closes it.
2. Before any rung-3+ change, complete the capability-parity checklist.
3. Apply the fix, run the existing suite unchanged-green, then commit and push only when the user explicitly requested it.

## The ladder (stop at the first rung that closes the finding)

0. **Widening enumeration** — when the finding asks you to WIDEN a guard, timeout, or validation scope: list every population newly covered by the wider guard and confirm each population's normal path survives the guard. Widening is substitution's sibling regression source (VOY-736: watchdog widened to all sessions → cut in-flight I/O at 60 s → next round found the load-phase gap → three consecutive P1s).
1. **Detection only** — verify/pin/lstat-compare around the existing call (identity check before and after the untrusted window).
2. **Pin beside the path** — keep the path-based operation, pin what it operates on with an fd (`O_NOFOLLOW`, `O_DIRECTORY`) and apply metadata via `fchmod`/`futimes` on the fd.
3. **Atomic reserve** — `O_CREAT | O_EXCL` name reservation plus verified `renameat`, only when detection cannot close the hole.
4. **Full mechanism replacement** — allowed inside a review-fix cycle only when detection, pinning, or atomic reservation cannot close the finding. Complete the capability-parity checklist and RED-first regression evidence before landing it.

## Capability-parity checklist (mandatory before ANY rung-3+ change lands)

The old mechanism's implicit capabilities are the regression surface. Check every one:

- [ ] Cross-device (rename/copy across volumes — `EXDEV`; `moveItem` handled this, `renameat` does not)
- [ ] Special files (FIFO, device nodes, sockets, package dirs)
- [ ] Sparse files / hole preservation
- [ ] Extended attributes, resource forks, metadata (mode, times, flags)
- [ ] Error and cleanup paths (partial artifacts, rollback)
- [ ] Performance characteristics (memory ceilings, syscall granularity)

A miss on any box means: add the fallback or defer the swap.

## Failure evidence (VOY-736, PR #506, 2026-08)

All three happened while satisfying security findings by substitution:

1. `copyfile` status callback (`STATUS_CB`/`STATUS_CTX`) for mid-copy abort → reproducible **SIGBUS** in Swift interop; binary-search isolated the callback installation.
2. `fcopyfile(COPYFILE_ALL)` → manual chunk copy + xattr duplication swap → **42 test failures** (sparse/xattr integrity collapse). Rolled back.
3. `moveItem` → `renameat` swap for exclusive-name claim → silent **cross-volume (EXDEV) drop failure**; the old copy+delete fallback capability was dropped without a checklist entry.

Each replaced code that worked to defend against an attack that had never been observed.

## Swift editing pitfall (two-stage parameter edits)

Adding a parameter to a signature FIRST and its body references in a LATER edit gets the unused parameter name discarded to `_:` by the edit-time swiftformat hook (e.g. `shouldAbort _:`), which fails compilation with `cannot find ... in scope` on the second edit. Add the parameter and its first body reference in the SAME edit; when you see that error after a multi-stage edit, suspect `_:` discarding before anything else. (VOY-736: three such compile failures in one cycle.)

## Hard rules

- A swap that lands must carry a fallback for every checklist capability the old mechanism had (or a test proving the capability is unreachable).
- If substitution is the only real fix: run the capability-parity checklist and add a RED-first regression test. When both prove equivalence, replace within the current change. Only reply "deferred" and create a follow-up issue when parity cannot be proven — never ship a known defect just to avoid a rewrite.
- After any hardening fix, run the existing suite unchanged-green before push. A new failure means the guard broke the mechanism — revert the guard, not the tests.
- If two attempts at the same substitution fail (crash or regressions), stop. Revert to the last green state and document the residual window instead of forcing the third attempt.

## Verification

- Existing suite passes unchanged after the fix.
- The specific attack scenario named by the reviewer has either a check/test or an explicitly documented residual window in the reply comment.
- `git diff` shows the mechanism's original call site preserved (rungs 1–2) or a completed checklist (rung 3+).
