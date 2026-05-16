# Voyager Dev Shell Freeze and Shared Promotion

## Use when

- A shell or public surface has reached stability and needs a formal freeze point.
- Evaluating whether a slice-local utility qualifies for promotion into `06_Shared`.
- A previously promoted utility shows signs of becoming slice-specific and needs rollback.

## Scope

Two related ceremonies in one document. Shell-freeze is the typical trigger for shared promotion: when a surface stabilizes, the natural next question is whether its reusable pieces belong in `06_Shared`. Treating them together avoids a procedural gap where frozen surfaces drift without promotion evaluation.

## Canonical neighbors

- `../../../reviewer/boundary/references/public-boundary-spec.md` — public surface rules, deep import rules, entity cross-reference
- `../../../reviewer/boundary/references/layer-and-segment-rules.md` — FSD layer contracts, `06_Shared` contract, dependency direction
- `reuse-discovery-spec.md` — reuse-first ordering, candidate table format, search workflow
- `../../../reviewer/architecture-gate/references/decision-matrix.md` — Reuse Score model, thresholds, output contract
- `../../scaffold/references/package-extraction-posture.md` — extraction readiness checks, modularization direction

## Non-goals

This reference does NOT cover:

- Reuse scoring or the Reuse Score formula (see `../../../reviewer/architecture-gate/references/decision-matrix.md`)
- Public boundary principles or deep import rules (see `../../../reviewer/boundary/references/public-boundary-spec.md`)
- `06_Shared` layer contract or what shared code may reference (see `../../../reviewer/boundary/references/layer-and-segment-rules.md`)
- Reuse search workflow or candidate discovery (see `reuse-discovery-spec.md`)
- Extraction readiness checks (see `../../scaffold/references/package-extraction-posture.md`)

---

## Part 1: Shell-freeze ceremony

### Triggers

Run the freeze ceremony when ALL of the following are true:

1. **Extraction complete.** Package extraction is finished or the public surface has been confirmed stable through review.
2. **No planned signature changes.** No outstanding work items propose changes to the shell's public API signatures.
3. **At least one consuming caller.** At least one caller outside the shell's own slice relies on the current surface. A surface with zero external consumers has no reason to freeze.
4. **Clear ownership.** The owner audit (from `../../decompose/references/orchestrator-spec.md`) shows conflict-free ownership: each state field, effect, and cancellation scope has exactly one canonical owner.

### Steps

**Step 1: Audit the public surface.** List every exposed type, function, and property that callers outside the slice can reach. Record the list as a surface manifest.

**Step 2: Verify extraction readiness.** Run the extraction-ready checks from `../../scaffold/references/package-extraction-posture.md`. Freeze should not proceed if the surface would break when moved behind a package boundary.

**Step 3: Document the frozen surface manifest.** Write down:

- Every locked type and its signature
- Stability guarantees (what callers can rely on)
- Any known constraints callers should be aware of

**Step 4: Mark the surface as frozen.** Add a code comment or documentation annotation at the public surface entry point indicating freeze status. The annotation should name the freeze date and link to the manifest.

**Step 5: Establish a change review policy.** Define who approves changes to the frozen surface, what evidence a change request must include, and how quickly reviews should happen.

### Review outputs

After the ceremony, the following artifacts should exist:

| Artifact                     | Content                                                           |
| ---------------------------- | ----------------------------------------------------------------- |
| Frozen surface manifest      | List of locked types and signatures with stability guarantees     |
| Change review policy         | Who approves, what evidence is required, expected turnaround      |
| Compatibility shim allowance | Rules for temporary wrappers that preserve backward compatibility |

### Post-freeze change policy

| Change type              | Policy                                                                                                        |
| ------------------------ | ------------------------------------------------------------------------------------------------------------- |
| Bug fix                  | Allowed without ceremony. Do not change signatures.                                                           |
| New addition (extension) | Allowed. Extensions, new overloads, and new types added alongside the frozen surface do not require unfreeze. |
| Signature change         | Requires explicit unfreeze or a compatibility shim. The shim must have a sunset timeline.                     |
| Removal                  | Requires a deprecation notice with a sunset period. All consumers must migrate before removal.                |

---

## Part 2: Neutral utility qualification

### Qualification criteria

A utility qualifies for `06_Shared` promotion only when it meets ALL five criteria:

1. **Slice-agnostic.** No references to app-, page-, feature-, or entity-specific types. The utility operates on primitives, standard library types, or its own self-contained domain.

2. **Multi-caller.** Proven use from at least 2 distinct callers across different slices. Two callers within the same slice do not count.

3. **Stable interface.** The utility's public interface is unlikely to change for slice-specific reasons. If one slice's evolving needs drive API churn, the utility is not ready.

4. **Layer-agnostic.** The utility can be consumed from any FSD layer without creating upward dependencies. It does not import types from `01_App`, `02_Pages`, `03_Widgets`, `04_Features`, or `05_Entities`.

5. **Testable in isolation.** The utility can be tested without pulling in slice-specific test infrastructure. Its tests use only standard library, XCTest, and shared test helpers.

### Slice-local retention criteria

Keep a utility slice-local when ANY of the following apply:

| Criterion          | Signal                                                                                |
| ------------------ | ------------------------------------------------------------------------------------- |
| Single caller      | Only one slice uses it. Wait for a second caller before promoting.                    |
| Domain-specific    | The utility references types, protocols, or concepts from a specific business domain. |
| Evolving interface | The API is still changing based on one slice's needs. Freeze the interface first.     |
| Testing coupling   | Tests require slice-specific mocks, fixtures, or infrastructure to run.               |

---

## Part 3: Rollback and sunset guidance

### When to rollback a promoted utility

A promoted utility should be rolled back when ANY of these conditions emerge:

- **Domain-specific drift.** The utility gains a caller or parameter that makes it reference a specific domain, breaking slice-agnosticism.
- **Single-slice evolution.** The utility's interface starts changing to serve one slice's needs, breaking the stable-interface criterion.
- **Test coupling.** The utility can no longer be tested without pulling in slice-specific infrastructure.

### Rollback procedure

**Step 1: Identify the trigger.** Pinpoint the slice-specific dependency that caused the utility to fail qualification. Document it.

**Step 2: Create a slice-local copy or adapter.** In the consuming slice that needs the domain-specific behavior, create a local copy or an adapter that wraps the shared utility and adds the slice-specific logic.

**Step 3: Deprecate the shared version.** Mark the shared utility with a deprecation annotation. Include a migration note pointing callers to the slice-local replacement and a sunset date.

**Step 4: Remove after convergence.** Once all consumers have migrated to their slice-local copies or adapters, remove the deprecated shared version. Do not leave deprecated code in `06_Shared` indefinitely.

### Compatibility shim lifecycle

Compatibility shims are temporary constructs that preserve the frozen surface during transitions.

| Shim type                                                              | Policy                                                                                                                                               |
| ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Thin forwarding wrapper (owns real translation or boundary protection) | Allowed. The wrapper converts between old and new signatures, or it enforces a boundary constraint. Give it a sunset date.                           |
| Passthrough wrapper (compatibility-only, no real behavior)             | Not allowed. If the wrapper does nothing but forward calls with no translation, it is noise. Either commit to the new signature or keep the old one. |

**Sunset lifecycle for shims:**

1. Create the shim with a deprecation annotation naming a removal date or version.
2. Update all callers to use the new path before the removal date.
3. Remove the shim once all callers have converged.
4. Do not extend the sunset date without a documented reason and re-review.

---

## Required output

After performing a freeze or promotion ceremony, the worker must produce:

1. **Frozen surface manifest**: list of every locked type and its signature, with stability guarantees and known constraints.
2. **Promotion decision**: promote / retain / rollback, with the specific qualification criteria that passed or failed.
3. **Evidence record**: caller count, caller slice names, upward-dependency check result (for promotion), or the specific trigger condition (for rollback).
4. **Rollback readiness**: confirmation that rollback triggers and procedure are documented for any promoted utility.

---

## Verification

After performing a freeze or promotion, verify:

```bash
# Confirm frozen surface annotations exist
grep -r "frozen" --include="*.swift" <slice-path>

# Confirm promoted utility has no upward dependencies
grep -r "import.*\(App\|Pages\|Widgets\|Features\|Entities\)" <shared-utility-path>

# Confirm multi-caller proof (at least 2 distinct caller sites)
# Use lsp_find_references on the promoted symbol
```

For rollback verification, confirm the deprecated shared version has zero callers remaining before removal.
