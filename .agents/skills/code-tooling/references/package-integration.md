# Voyager Dev Package Integration Verification

Use this reference when a Voyager local SwiftPM package is created, deleted, segmented, renamed, or when `Package.swift` products, targets, dependencies, access surface, or consumer wiring change.

## Principle

Package-local verification proves the package can compile by itself. Integration verification proves the package is still consumable by the app, hosts, tests, and downstream packages that rely on its products. Each verification layer must pass before moving to the next. A failure at any layer means stop and fix before proceeding.

## When to load

- A package manifest changes: products, targets, dependencies, target membership, or product names.
- A new package, product, or target is introduced under `apps/macos/Packages/**`.
- A package, product, target, dependency edge, or consumer link is removed.
- Public API, exported types, imports, or module names change.
- Files are moved inside a package in a way that may expose stale Xcode, linker, or consumer assumptions.
- `swift build --package-path` passes but the selected consumer build route fails.
- Imports need auditing before removal, or public surface exposure needs checking.
- Linker errors appear after dependency changes, or test targets need wiring verification.

## Verification layers

```
Layer 1: Package build        → does the package compile by itself?
Layer 2: Package tests        → does the package's own test suite pass?
Layer 3: Consumer build       → can the app/host link and import the package?
Layer 4: Consumer tests       → do the app/host tests pass with the changed package?
```

Layer 1 passing while Layer 3 fails is the most common integration problem. `swift build` only checks compilation inside the package — it does not exercise the product linking path that Xcode uses.

## Command surfaces

Use the capability matrix in `.agents/skills/code-tooling/SKILL.md`: package-local layers use `xcrun swift`, and macOS consumers use the repository's `mise` tasks. If another platform has no repository-defined executor, stop and report the missing verification route.

### Package-local SwiftPM route

Package-local:

```bash
xcrun swift build --package-path apps/macos/Packages/<Package>
xcrun swift test --package-path apps/macos/Packages/<Package>
```

For a macOS consumer boundary, use `mise run macos-build` and `mise run macos-test`. Use the narrowest repository-defined route that proves the changed product is linked and imported. Expand to the full app or host build when product exposure, target membership, or dependency removal can affect multiple consumers.

## Phase 1: Pre-change baseline

### 1.1 Capture build baseline

Run `mise run macos-build` before the change for the macOS development scheme. Record pass/fail and the first errors in task evidence.

### 1.2 Capture test baseline

Run `mise run macos-test` before the change for the macOS development scheme. Record total tests, failures, and failing test names in task evidence.

### 1.3 Save baseline state

Persist the selected executor, operation or command, target scope, exit result, and failing-test summary in task evidence. If the baseline has failures, document them for later classification.

## Phase 2: Make changes

Edit `Package.swift`, move files, change access levels, add/remove dependencies. Then proceed to layered verification.

## Phase 3: Layered verification

Verify in order. Each layer must pass before moving to the next.

### 3.1 Layer 1: Package build (fast feedback)

```bash
xcrun swift build --package-path apps/macos/Packages/<Package>
```

This checks that the package itself compiles. It does NOT verify that consumers can link against it.

**If this fails:** Fix compilation errors within the package. Do not proceed to Layer 2 until this passes.

### 3.2 Layer 2: Package tests

```bash
xcrun swift test --package-path apps/macos/Packages/<Package>
# Or focused:
xcrun swift test --package-path apps/macos/Packages/<Package> --filter 'TestPattern1|TestPattern2'
```

This checks the package's own test suite. If the package has no tests, skip this layer.

**If this fails:** Fix test failures. Do not proceed to Layer 3 until this passes.

### 3.3 Layer 3: Consumer build (integration boundary)

For macOS consumers, run `mise run macos-build`. For another platform, use its repository-defined consumer build task or stop and report the missing route.

**Common failure modes at this layer:**

| Error pattern                         | Cause                                                                  | Fix                                                                                                 |
| ------------------------------------- | ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `Undefined symbol` for a package type | Consumer target not linked to the package product                      | Add explicit link product reference in Xcode project for the consuming target                       |
| `Could not find module`               | Package product not declared or not added to the target's dependencies | Check Package.swift products array and Xcode target's "Frameworks, Libraries, and Embedded Content" |
| `Re-export chain broken`              | A type was moved out of a module that re-exports it                    | Update the re-export or move the type back                                                          |
| `Linker error: duplicate symbol`      | Same symbol in both package and consumer target                        | Ensure the file is only in one place (package or target, not both)                                  |

**If Layer 1 passes but Layer 3 fails:** The problem is at the integration boundary, not the package source. Focus on linking, product declarations, and target dependencies.

### 3.4 Layer 4: Consumer tests

For macOS consumers, run `mise run macos-test`. For another platform, use its repository-defined consumer test task or stop and report the missing route.

Run focused tests first when the change scope is narrow, then expand to the full suite.

**If Layer 3 passes but Layer 4 fails:** The build links correctly but behavioral tests catch regressions. Triage failures (see Phase 8).

### 3.5 Static proof points

After all four layers pass:

- [ ] `xcrun swift build --package-path apps/macos/Packages/<Package>` passes (Layer 1)
- [ ] `xcrun swift test --package-path apps/macos/Packages/<Package>` passes or no tests exist (Layer 2)
- [ ] Matrix-selected consumer build passes (Layer 3)
- [ ] Matrix-selected consumer test passes (Layer 4)
- [ ] No new warnings introduced (check the build log)
- [ ] DerivedData was clean or stale artifacts were ruled out

## Phase 4: Import audit

### 4.1 Identify imports to audit

```bash
# List all imports from the affected module across the codebase
grep -rn "import <ModuleName>" --include="*.swift" apps/macos
```

### 4.2 For each import, verify it is actually needed

Do NOT remove imports based on grep alone. Swift member access resolution requires the defining module import even when the type name never appears literally in source.

A module import is required when a file does any of the following:

1. **Direct type reference:** The file explicitly names a type from the module

    ```swift
    let foo: SomeModuleType = ...
    ```

2. **Stored property typed as a package type:** Even if the type name comes from a typealias or generic parameter

    ```swift
    struct MyStruct {
        var payload: SomePackageType  // requires import SomePackage
    }
    ```

3. **Method calls on package-typed values:** The return type or parameter type comes from the package

    ```swift
    someValue.somePackageMethod()  // requires import even if someValue's type is inferred
    ```

4. **Associated value / payload member access:** Accessing enum cases or struct members defined in the package

    ```swift
    if case .someCase(let payload) = result {
        print(payload.field)  // field type comes from the package
    }
    ```

5. **Extension methods:** The file extends a type from the package, or calls extension methods defined on a package type

    ```swift
    extension PackageType { ... }  // requires import
    ```

6. **Protocol conformance:** The file conforms to a protocol defined in the package

    ```swift
    struct MyThing: PackageProtocol { ... }  // requires import
    ```

### 4.3 Safe removal procedure

For each import suspected to be unused:

1. Check all six categories above against the file's source
2. If none apply, temporarily remove the import
3. Build at Layer 3 using the matrix-selected consumer route, not just `swift build`
4. If build fails, the import was needed. Restore it.
5. If build passes, the import was unused. Leave it removed.

### 4.4 False positive patterns

These grep results look like the import is used, but check carefully:

- A type name appears in a string literal (not a code reference)
- A type name appears in a comment
- A type name matches a different type from another module (name collision)
- The import is needed indirectly through a re-export chain (removing it breaks a downstream file)

## Phase 5: Public surface audit

### 5.1 Identify newly public types

```bash
# Find public declarations in the package
grep -rn "public " --include="*.swift" apps/macos/Packages/<Package>/Sources
```

### 5.2 For each public declaration, verify necessity

Ask: does any consumer outside this package reference this symbol?

```bash
# Check if the symbol is used outside the package
grep -rn "<SymbolName>" --include="*.swift" apps/macos/Voyager apps/macos/Hosts apps/macos/Packages
```

### 5.3 Minimize public surface

- Start with `internal` (the default). Only promote to `public` when a consumer needs it.
- Helper functions, internal utilities, and test support code should stay `internal`.
- If a type is only used by the package's own tests, put it in a test target, not the main library target.
- Use `public` on the minimal set: the init, the properties consumers read/write, and the methods they call.

### 5.4 Verify no over-exposure

```bash
# Check for public properties that might leak implementation details
grep -rn "public var\|public let\|public func" --include="*.swift" apps/macos/Packages/<Package>/Sources
```

For each result, confirm a consumer actually uses it. If not, downgrade to `internal`.

## Phase 6: Test target wiring

### 6.1 Identify test targets that use the package

```bash
grep -rn "import <ModuleName>" --include="*.swift" apps/macos/Voyager/VoyagerTests apps/macos/Voyager/VoyagerUITests
```

### 6.2 Check link product references

In Xcode:

1. Select the project in the navigator
2. Select the test target
3. Go to "General" > "Frameworks and Libraries" (or "Build Phases" > "Link Binary With Libraries")
4. Verify the package product is listed

App targets resolve package dependencies automatically in most cases. Test targets usually require explicit link product references. If missing, add the package product explicitly.

### 6.3 Verify test compilation and linking

Run the matrix-selected consumer test route and inspect the result for linker errors. If `Undefined symbol` appears for package types, the test target is missing a link product reference.

## Phase 7: Dependency evidence table

### 7.1 Template

Create a table for each dependency affected by your changes:

```markdown
| Package  | Product  | Source files using it                    | KEEP/REMOVE | Build verification   |
| -------- | -------- | ---------------------------------------- | ----------- | -------------------- |
| PackageA | ProductA | Sources/File1.swift, Sources/File2.swift | KEEP        | pass                 |
| PackageB | ProductB | Tests/File3.swift                        | REMOVE      | pass (after removal) |
```

### 7.2 Fill in the table

1. **Package:** The SwiftPM package name
2. **Product:** The specific product from that package (a package can have multiple)
3. **Source files:** All files outside the package that import it
4. **KEEP/REMOVE:** Your decision with justification
5. **Build verification:** Fill in ONLY after running all four verification layers with the change applied

### 7.3 Verify each row

For REMOVE decisions:

- Remove the import from all listed source files
- Remove the dependency from Package.swift (or the Xcode project)
- Run Layer 3 (consumer build)
- Record result

For KEEP decisions:

- Verify the import is still needed (see Phase 4)
- Run Layer 3 (consumer build)
- Record result

## Phase 8: Test failure triage

### 8.1 Run post-change tests

Run the same matrix-selected consumer test route used for the baseline, focused first and broadened only when the changed boundary requires it.

### 8.2 Diff against baseline

Compare the failing-test names recorded in baseline evidence with the names recorded after the change.

### 8.3 Classify each failure

For each failing test:

1. **Get the test name** from the failure output
2. **Check if it references any symbol changed in your diff:**
    ```bash
    # List symbols changed in your diff
    git diff --name-only HEAD~1
    ```
3. **Classification:**
    - `CAUSED_BY_CURRENT`: The failing test references a file, type, or function that appears in your diff
    - `PRE_EXISTING`: The test was already failing in the baseline, or references symbols untouched by your changes
4. **Action:**
    - `CAUSED_BY_CURRENT`: Fix before proceeding. This is your responsibility.
    - `PRE_EXISTING`: Document in a separate section. Do not fix as part of this change unless explicitly asked.

### 8.4 Document classification

```markdown
## Test failure classification

### CAUSED_BY_CURRENT

- TestFoo/testBar: Fixed in commit abc123

### PRE_EXISTING (not addressed)

- TestBaz/testQux: Fails in baseline too. Unrelated to package changes.
```

## Common mistakes

1. **Stopping at Layer 1 (package build).** The package compiling by itself does not prove consumers can link or import it. Each layer catches different failure modes.

2. **Grepping for type names to justify import removal.** A file can depend on a module without ever spelling out its type names. Stored properties, method return types, and associated value access all require the import.

3. **Blanket `public` on moved types.** Exposing everything creates a maintenance burden and couples consumers to implementation details. Start minimal.

4. **Forgetting test target link wiring.** The app target often auto-resolves. Test targets usually do not. If tests fail with linker errors (`Undefined symbol`), this is the first thing to check.

5. **Mixing pre-existing failures with current changes.** Always capture a baseline. If you skip this step, you will waste time debugging failures unrelated to your work.

6. **Removing a dependency without checking transitive consumers.** Package A might not use Package C directly, but Package B (which A depends on) might. Check the full dependency graph before removing.

## Failure mode reference

### Build fails at Layer 3 only (consumer boundary)

Symptoms: `swift build` passes, but the matrix-selected consumer build fails.

Causes:

1. Missing link product reference for the consuming target
2. Re-export chain broken by moving a type
3. Package product not declared in the products array
4. Stale DerivedData caching old module interfaces

Fixes:

1. Add the package product to the target's link list
2. Update re-exports or add a forwarding typealias
3. Add the product to `Package.swift` products array
4. Clean DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData/<project>-*`

### Linker errors in test target

Symptoms: `Undefined symbol` errors when building or running tests.

Cause: Test target missing explicit link product reference for the package.

Fix: Add the package product to the test target's "Frameworks, Libraries, and Embedded Content" or "Link Binary With Libraries" build phase.

### False clean build after removal

Symptoms: Removed a dependency but everything still compiles.

Cause: The dependency is still resolved transitively through another package.

Check: Look at the resolved dependency graph. The removed package might be pulled in by another path.

```bash
# Check dependency graph
xcrun swift package show-dependencies --package-path apps/macos/Packages/<Package>
```

### Tests pass locally but fail in CI

Symptoms: Different behavior between local and CI environments.

Causes:

1. CI has a clean build (no stale cache), local has cached artifacts
2. Different simulator or SDK version
3. CI resolves dependencies differently (different Package.resolved)

Fix: Use the matrix-selected repository or supported MCP route with a clean build only when its cleanup capability is exposed and the cleanup is in scope. Record the environment difference and result in evidence.

### SourceKit or LSP stale module context

Symptoms: SourceKit or LSP reports `No such module` while an Xcode consumer build succeeds.

Cause: The editor context is stale after moving files or changing targets.

Fix: The Xcode consumer build is the real source of truth. Restart SourceKit if needed (`Editor > SourceKit > Clear Cache` or restart the IDE).

### Import-only cleanup misses manifest wiring

Symptoms: Grep-based import cleanup passes but the build still fails.

Cause: Package manifest, product dependency, or test-target wiring was not updated alongside import changes.

Fix: Verify `Package.swift` products array, Xcode target dependencies, and test target link references — not just source imports.

## pbxproj hygiene

The Voyager project (`apps/macos/Voyager/Voyager.xcodeproj`) uses `PBXFileSystemSynchronizedRootGroup` for file discovery. This means:

- **Adding files**: Place on disk in the correct directory. Xcode auto-discovers on next project load. Do NOT manually add `PBXFileReference` or `PBXBuildFile` entries.
- **Deleting files**: After `rm`, grep the pbxproj for the filename. Check specifically in `PBXFileSystemSynchronizedBuildFileExceptionSet` sections for orphaned entries referencing the deleted path. Remove those entries. If the exception set becomes empty, remove the entire block.
- **Moving files**: `git mv` then check pbxproj for stale references at the old path. Under synchronized root groups, Xcode handles this on reload.

```bash
# After deleting a file, verify pbxproj is clean
grep -c "DeletedFileName" apps/macos/Voyager/Voyager.xcodeproj/project.pbxproj
# Should output 0
```

## Package Build Blocker Evidence Matrix

When a SwiftPM package build fails before changed tests compile, do NOT mark verification as passed.

Record the following evidence:

| Field              | Value                                     |
| ------------------ | ----------------------------------------- |
| Package path       | `apps/macos/Packages/...`                 |
| Suite filter       | `--filter <SuiteName>`                    |
| Exit code          | [code]                                    |
| Failure phase      | compilation / test-execution              |
| First failure path | [file:line]                               |
| Blocker owner      | Source code (not test code) / Test code   |
| Pre-existing?      | Yes / No                                  |
| Proof gap          | Yes — changed tests NOT proven to compile |

### Classification rules

- **Pre-existing source blocker**: Build fails in package source code not modified by the current task. Record as BLOCKED, proof gap.
- **Test-caused blocker**: Build fails in test code modified by the current task. Fix and re-run.
- **Infrastructure blocker**: Build fails due to missing dependencies or toolchain issues. Record as BLOCKED, try to resolve.
