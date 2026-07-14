---
description: "Design rules for TCA dependency clients: granularity, composition, phantom elimination, and macro policy."
globs: "apps/macos/**"
---

# Dependency Client Design

Governs how `Api/*Client.swift` types are split, composed, and registered. Extends the client introduction rules in `.agents/skills/voyager-dev/implementer/tca-contract/references/tca-contract.md` (Dependency client rules). Read that reference first for placement and introduction criteria.

## Must

- Split clients along reducer-capability boundaries that map to a single infrastructure seam (file I/O, network, system API, persistence).
- Register a client as `DependencyKey` only when at least one reducer consumes it via `@Dependency(\.clientKey)`.
- Compose clients that depend on other clients using one of:
    - A `static func live(_:otherClient:) -> Self` factory that accepts the dependency as a parameter, called from `liveValue`.
    - `@Dependency(\.otherClient)` resolved inside the closure body, not in the `liveValue` computed property body (which caches the resolution once).
- Provide `testValue` and `previewValue` for every registered client. Prefer explicit, named mocks over `unimplemented` stubs so test intent stays readable.
- Name clients after the capability they expose (`AccountSessionClient`, `AuthNetworkClient`), not the implementation (`KeychainClient`, `URLSessionClient`) when the capability spans multiple backends.
- Treat a client as a private implementation detail (not a `DependencyKey`) when only another client's `liveValue` consumes it; inline it as a helper type or function.
- Sequence cross-seam operations (e.g., network result → file persist) via a reducer-private helper function. Do not introduce a new `DependencyKey` for this purpose.

## Must not

- Register a client as `DependencyKey` when no reducer uses it directly. This is a phantom dependency; inline the logic into the sole consumer or remove the registration.
- Reference `OtherClient.liveValue` inside a method closure of another client's `liveValue`. This bypasses `withDependencies` overrides (Premature Dependency Capture).
- Mix multiple infrastructure seams in a single client (e.g., file token read + network refresh + system URL open). Split per seam.
- Introduce the `@DependencyClient` macro in a single package. The codebase uses manual `DependencyKey` conformance everywhere; adopt the macro only as a coordinated migration across all packages.
- Add a new `*Client.swift` for a capability an existing client already owns. Extend the existing client or split both along the seam, do not overlap.
- Expose `refreshToken`-style internal lifecycle methods on a public client when only one other client calls them; make them private helpers.

## Execution steps

1. Identify the reducer capability the new work needs (e.g., "restore session", "exchange handoff ticket", "open billing URL").
2. Map each capability to exactly one infrastructure seam: file I/O, network HTTP, system API (NSWorkspace/Keychain/UserDefaults), or actor-backed state.
3. Check existing clients in the package and `06_Shared/Api` for a capability match:
    - Match found and same seam → extend the existing client.
    - Match found but different seam → split the existing client per seam first.
    - No match → introduce a new client.
4. Verify the candidate client has at least one reducer consumer. If only another client's `liveValue` will call it, treat it as a private helper, not a `DependencyKey`.
5. Choose the composition pattern:
    - Single dependency → factory function `static func live(_:)`.
    - Multiple dependencies or test override needed → `@Dependency(\.)` inside each closure.
6. Write `liveValue`, `testValue`, and `previewValue`. Ensure `testValue` fails loud (throw or assert) on unintended use.
7. Add the `DependencyValues` extension in the same file as the client struct.
8. When a flow spans multiple client seams (e.g., exchange ticket → persist session), extract a private helper in the reducer (e.g., `performHandoffExchange`) that sequences the calls. The helper captures the needed clients and chains their methods inside a single `.run` effect.

## Verification

- Every registered `DependencyKey` has at least one `@Dependency(\.key)` reference in a `@Reducer` struct under `apps/macos/**`. Search: `ast-grep` or `grep` for the key path.
- No `OtherClient.liveValue` reference appears inside a closure literal within a different client's `liveValue`. Search: `grep -rn '\.liveValue\.' apps/macos/Packages/**/Api/*Client.swift` and inspect each hit's enclosing scope.
- No client struct mixes more than one infrastructure seam. Inspect `liveValue` body: file `URL`, `URLSession`, `NSWorkspace`, `UserDefaults`, `Keychain`, or actor `shared` should not co-occur in the same struct.
- `@DependencyClient` macro is absent from the codebase until a coordinated migration is approved. Search: `grep -rn '@DependencyClient' apps/macos/`.
- `testValue` and `previewValue` are present for every `DependencyKey` conformance.
