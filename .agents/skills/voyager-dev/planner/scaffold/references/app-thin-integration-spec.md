# Voyager Dev App-Thin Integration Spec

## Use when

- Wiring an extracted package into the app shell after extraction readiness is confirmed.
- Deciding what `01_App` may own versus what must stay package-local.
- Defining helper/XPC boundary contracts between app and helper processes.
- Introducing or removing typealias bridges between package types and app namespace.
- Auditing the integration surface between app and extracted packages.

## Scope

This reference covers **integration ceremony only**: how the thin app shell wires to extracted packages, how helper/XPC boundaries are structured, and how temporary compatibility bridges are managed.

**Extraction readiness evaluation** belongs in `package-extraction-posture.md`. This reference assumes readiness is confirmed before integration begins.

## Canonical neighbors

| Neighbor                                                         | What it provides (linked, not restated)                         |
| ---------------------------------------------------------------- | --------------------------------------------------------------- |
| `package-extraction-posture.md`                                  | Extraction readiness checks and modularization direction        |
| `../../../reviewer/review/references/layer-and-segment-rules.md` | `01_App` and `06_Shared` layer contracts, dependency direction  |
| `../../../reviewer/review/references/public-boundary-spec.md`    | Public surface rules, deep import rules, entity cross-reference |
| `../../../implementer/tca-contract/references/tca-contract.md`   | Dependency client definition mechanics, `Sendable` rules        |

## Non-goals

- Extraction readiness evaluation (see `package-extraction-posture.md`).
- FSD layer definitions and `01_App` contract details (see `../../../reviewer/review/references/layer-and-segment-rules.md`).
- TCA dependency client definition mechanics (see `../../../implementer/tca-contract/references/tca-contract.md`).
- Public boundary stability principles (see `../../../reviewer/review/references/public-boundary-spec.md`).

---

## App-thin ownership

### ALLOWED in `01_App`

- **Composition wiring**: importing package types and composing them into the app's reducer tree.
- **Lifecycle bootstrap**: starting/stopping app-level services, registering app-wide dependencies.
- **Navigation routing**: routing between top-level windows/screens using package-provided features.
- **Window shell coordination**: managing window lifecycle, menu command dispatch, global keyboard shortcuts.
- **Top-level error/global state**: app-wide error presentation, global loading state, app-wide preferences.
- **App-wide dependency client registration**: registering clients in `01_App/Api/` only when the boundary is truly app-global (not domain-specific).

### FORBIDDEN in `01_App`

- **Domain logic**: any business rule that belongs to a feature, entity, or page package.
- **Domain state**: feature-specific or entity-specific `State` fields.
- **Domain-specific dependency clients**: clients that serve a single package's domain boundary. These belong in the package's `Api/` segment.
- **Feature/page-specific business rules**: rules that apply within one package's scope.
- **Package-internal implementation details**: any type or function that is not on the package's declared public surface.

### Principle

If a piece of logic would still make sense when the package is extracted to a standalone Swift Package, it must not live in `01_App`. The app shell is orchestration, not domain.

---

## Helper/XPC boundary responsibilities

### What lives in the helper process

- Background indexing, file scanning, and search operations.
- Long-running compute tasks that should not block the main app process.
- Any work that needs elevated or restricted entitlements separate from the app.

### What the app-side contract looks like

- The app communicates with the helper through an **XPC protocol**: a typed message interface, not direct function calls.
- The protocol defines request/response types and serialization requirements. Both sides agree on this contract.
- The app owns the protocol definition when the helper is an implementation detail of the app. If the helper is shared across multiple consumers, the protocol lives in a shared package.

### Error propagation rules

- Helper errors must not leak implementation details to the app. Wrap internal errors into domain-meaningful error types at the XPC boundary.
- The app-side receives a typed error from the XPC call. It must not parse or depend on the helper's internal error strings, error hierarchies, or log formats.
- Serialization failures at the XPC boundary are a boundary concern, not a domain concern. Handle them at the integration layer, not in domain reducers.

### Implementation independence

- Code on one side of the XPC boundary must not assume implementation details of the other.
- The app does not know how the helper indexes files, which database it uses, or which algorithms it runs.
- The helper does not know which reducers consume its results, which UI presents them, or which navigation state the app maintains.
- Changes to the helper's internals must not require changes to app code, and vice versa.

---

## Dependency client bridge procedure

### Where to define clients

Dependency client placement follows the three-tier rule in `../../../implementer/tca-contract/references/tca-contract.md` (dependency client rules): package-local `Api/` for package-domain boundaries, `01_App/Api/` for truly app-global services, and `06_Shared/Api/` for genuinely cross-cutting, layer-agnostic boundaries. This reference does not restate the placement rules; consult `../../../implementer/tca-contract/references/tca-contract.md` for the authoritative definition.

### Typealias bridge pattern

A typealias bridge re-exports a package type into the app's namespace for temporary compatibility:

```swift
// In 01_App, after package extraction:
typealias FileManagerWindowFeature = FileManagerFeature
```

**When to introduce**: package extraction is complete, but app call sites still reference the old app-local type name. The typealias preserves namespace compatibility during migration.

**When to remove**: all call sites use the package type directly (`FileManagerFeature` instead of `FileManagerWindowFeature`). No code references the typealias name.

### Duplicate type pitfalls

- **Never define the same type in both package and app.** If a type exists in the package, the app must use a `typealias` or import the package type directly — not re-declare it.
- Duplicate types cause "ambiguous for type lookup" errors when both the app module and the package module are imported simultaneously (especially in test targets using `@testable import`).
- When converting an app type to a package typealias, **remove all app-side extensions and conformances** for that type. The package already defines them; keeping app-side duplicates creates conflicting conformances.

### `@testable import` considerations

- Test targets validating package behavior should import the package directly (`@testable import PackageTarget`), not `@testable import Voyager` (the app target).
- Importing both the app target and the package target in the same test file creates duplicate type resolution errors.
- After converting an app type to a package typealias, test files that need internal access to the type must use `@testable import` on the **package** target, not the app target.

### `MemberImportVisibility` impact

- Swift 6's `MemberImportVisibility` feature means files calling extension methods on a typealiased type may need to import the original module.
- Stored property access does not require the extra import; only extension methods do.
- After introducing a typealias bridge, verify that call sites using extension methods on the typealiased type still compile. Add the package import where needed.

---

## Bridge/sunset language

### When to introduce a typealias bridge

1. Package extraction is complete and the type now lives in the package.
2. App call sites reference the old app-local name.
3. Immediate migration of all call sites would be disruptive (large diff, multiple files, risk of merge conflicts).
4. Introduce: `typealias OldAppName = PackageModule.PackageType`.

### When to remove

1. All call sites have been updated to use the package type directly.
2. No code references the typealias name (verify with workspace search).
3. Remove the typealias file and its import.

### Compatibility shim lifecycle

- Thin forwarding wrappers are acceptable as temporary bridges. They must own **real translation** (adapting one interface to another), not be passthrough wrappers that add no value.
- A passthrough wrapper (one that simply forwards all calls without transformation) is a sign the typealias should be removed instead.
- Compatibility shims must not accumulate domain logic. If a shim starts gaining real behavior, it is no longer a shim — promote the logic to the appropriate owner (package or app).

### Sunset documentation

- Mark all temporary bridges with a sunset comment:
    ```swift
    // TODO(sunset): remove when call sites converge to use PackageModule.PackageType directly
    typealias OldAppName = PackageModule.PackageType
    ```
- Track sunset bridges in the integration surface audit.
- Sunset bridges are debt. They must not become permanent. Schedule removal in a follow-up task.

---

## Integration surface audit

Perform this audit after each package extraction to verify minimal, correct integration.

### Step 1: List all app files that import the package

```bash
grep -r "import VoyagerPackageName" apps/macos/Voyager/Voyager/01_App/
```

Count the files. Target: **minimal** (ideally under 5 files for a single extracted package).

### Step 2: Verify each import touches only the package's public surface

For each file found in Step 1, inspect its usage of package types. Every referenced type must be:

- A public type declared in the package's public surface, or
- A typealias bridge documented with a sunset comment.

No file should reference package-internal types, fileprivate helpers, or implementation details.

### Step 3: Verify no package-internal types leak into app code

Search app code for any type name that exists only in the package's `internal` declarations:

```bash
# From the package source, list internal types, then grep app code for them
grep -rn "internal struct\|internal class\|internal enum\|internal protocol" \
  apps/macos/Packages/<Layer>/<PackageName>/Sources/<ProductName>/
```

If any of these internal types appear in `01_App/`, the boundary is leaking.

### Step 4: Verify no duplicate types exist between package and app

For each public type in the package, check whether an app-side file defines the same type name without a typealias:

```bash
# For each public type in the package, check app-side definitions
grep -rn "struct SameName\|class SameName\|enum SameName" apps/macos/Voyager/Voyager/01_App/
```

Duplicates must be converted to typealiases or removed.

### Step 5: Document the integration surface count

Record:

- Package name
- Number of app files importing the package
- Number of typealias bridges (with sunset status)
- Any open issues (leaked internals, duplicate types)

This record becomes the baseline for future integration audits.

---

## Required output

After performing the integration surface audit, the worker must produce:

1. **Integration surface record**: package name, number of app files importing the package, and list of typealias bridges with sunset status.
2. **Bridge inventory**: list of all active typealias bridges, each annotated with its sunset status (scheduled date or "none — requires follow-up").
3. **Duplicate-type check result**: confirmation that no duplicate types exist between package and app, or a list of violations to resolve.
4. **Boundary leak check result**: confirmation that no package-internal types appear in app code, or a list of leaked types.

---

## Verification

### Build verification

```bash
# Full build to catch integration errors
xcodebuild build -scheme Voyager-Dev \
  -project apps/macos/Voyager/Voyager.xcodeproj \
  -configuration Debug
```

### Duplicate type check

```bash
# Check for "ambiguous for type lookup" errors in build output
xcodebuild build -scheme Voyager-Dev \
  -project apps/macos/Voyager/Voyager.xcodeproj \
  -configuration Debug 2>&1 | grep "ambiguous for type lookup"
```

### Integration surface size check

```bash
# Count app files importing the package
grep -rl "import VoyagerPackageName" apps/macos/Voyager/Voyager/01_App/ | wc -l
```

### Sunset bridge inventory

```bash
# List all sunset bridges
grep -rn "TODO(sunset)" apps/macos/Voyager/Voyager/01_App/
```
