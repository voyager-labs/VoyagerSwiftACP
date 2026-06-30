# Voyager Dev Architecture Gate Spec

## Purpose

Block implementation choices that violate clean architecture or FSD dependency direction.

## Mandatory gates

1. Layer direction gate
    - Must satisfy:
        - `App -> Pages -> (Widgets|Features|Entities|Shared)`
        - `Widgets -> (Features|Entities|Shared)`
        - `Features -> (Entities|Shared)`
        - `Entities -> Shared`
2. Boundary gate
    - UI adapters must not call network/filesystem/system SDK directly.
    - External calls must go through dependency clients.
    - In UIKit/AppKit coordinators, react to feature state via TCA `observe { ... }`, not `store.publisher`/`sink`.
    - Do not introduce Combine-based state subscriptions in coordinators.
3. Slice boundary gate
    - Same-layer cross-slice references must be treated as a violation unless there is explicit architectural justification.
    - Do not depend on another slice's internal helpers or decomposition files when a stable boundary should exist.
4. Action boundary gate
    - UI adapters emit only `Action.view` or `@ViewAction` actions.
    - `delegate`/internal actions originate from reducer logic.
5. Reducer ownership gate
    - Non-trivial slices keep `State`/`Action` in `Model/`.
    - `Reducer/*Feature.swift` is orchestration-only.
    - New architecture split must not re-fragment `State`/`Action`/`Feature`/`Reducer` via `+*` extension files such as `State+Presentation.swift`; prefer dedicated mapper/projection/helper types.
6. Complexity inflation gate
    - Do not add new models, objects, wrappers, or reducers if an existing type can absorb the change with clearer ownership and lower overall complexity.
    - New wrapper layers created only for compatibility or guardrail reasons must prove they own real translation, migration, or protective behavior.
    - If a new type does not create a clearly new scope, treat it as a design smell and prefer extending or reshaping the existing type.
7. Layer vocabulary gate
    - Prefer standard Voyager/FSD segments (`Ui`, `Api`, `Model`, `Reducer`, `Lib`, `Config`).
    - Avoid introducing generic architecture buckets such as `Components`, `Types`, `Hooks`, or `Utils` as default segment names.
8. Dependency client design gate
    - Every registered `DependencyKey` has at least one `@Dependency(\.)` consumer in a `@Reducer`. No phantom dependencies.
    - No `OtherClient.liveValue` reference inside another client's method closure (Premature Dependency Capture). Use a factory function or `@Dependency` resolved inside the closure.
    - A single client must not mix multiple infrastructure seams (file I/O + network HTTP + system API). Split per seam.
    - Do not introduce the `@DependencyClient` macro in a single package; the codebase uses manual `DependencyKey` conformance everywhere.
    - See `.agents/rules/30-macos/11-dependency-client-design.md` for the full rule.
9. Custom URL scheme and callback target gate
    - macOS custom URL schemes are routed by LaunchServices to the preferred handler for the scheme, not to "the currently running app" or the app that initiated the flow.
    - Do not let Voyager app, dev builds, host apps, or helper apps rely on the same callback scheme when they must coexist on one machine.
    - Keep screen/business context separate from callback target identity: `context=onboarding` must not imply `OnboardingHost`.
    - Web/app handoff contracts must use an allowlisted target such as `app_target` and derive the callback scheme server-side; never trust a raw external `callback_scheme` value.
    - For dev/prod/host coexistence, check bundle identifiers, `CFBundleURLTypes`, Web redirect/callback contracts, parser allowlists, and fallback behavior together.
    - Required default target split: production app owns `voyager://auth/callback`; dev or host-only flows use distinct schemes such as `voyager-dev://auth/callback` or `voyager-onboarding-host://auth/callback`.

## Violation handling

- If any gate fails, do not proceed with implementation.
- Move candidate to `adapter` or `reject`, then pick next candidate.
- Record the failed gate and path in the decision output.

## Required output

- `architecture_passed: true|false`
- `failed_gates: []`
- `required_adapters: []`
