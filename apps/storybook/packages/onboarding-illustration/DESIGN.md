# Onboarding Illustration Design System

Storybook review surface for the current native Voyager onboarding window. Native source remains authority; this package is a deterministic web translation, not runtime proof.

## 1. Authority

- Shell and responsive geometry: `apps/macos/Packages/02_Pages/Onboarding/Sources/VoyagerPagesOnboarding/Ui/OnboardingView.swift`.
- Permissions: `PermissionsStepView.swift`.
- AI providers: `AiProviderSetupStepView.swift`.
- Completion: `CompleteStepView.swift`.
- Window frame/material: `OnboardingWindowController.swift`.

The reflected flow is `Welcome → Permissions → AI Provider → Start your voyage` in a `900×600` review fixture. The 60%-of-screen initial sizing and `1200×800` maximum remain native runtime behavior.

## 2. Tokens and material

- Shared controls, typography, system colors, window hairline, shadow, and material roles come from `@voyager-labs/design-foundation` through `--macos-*` aliases.
- `--onb-accent: rgb(252 154 48)` is the sole native-derived fixed-color exception, matching `OnboardingView.swift:91-95`.
- The HUD background and ultra-thin top bar use `--macos-material-hud-window` and `--macos-material-ultra-thin`. Browser compositing is a translation default because final AppKit material pixels vary by OS, appearance, transparency settings, and window activity.
- Base spacing unit is 4px. Native measurements are preserved where declared: 24px outer inset, 26px top inset, 12px main gap, 40px top bar, 12px card inset, 12px corner radius, 8px progress dots.

## 3. Reusable primitives

- `Button`: Back, Next, Complete, Retry, permission, and provider actions.
- `TextField`: API-key rows.
- `Toggle`: Launch at Login.
- `TrafficLights`: browser translation of native window chrome.
- `OnboardingWindow`: root composition and the only catalog integration point.

## 4. Deterministic states

Stories cover Welcome, blocked/granted/requesting Permissions, AI loading/error/mixed provider states, and Complete idle/opening/error. Fixtures contain no network, clock, random data, credentials, reducer execution, or OS permission probes.

## 5. Accessibility

- The window is a labelled region; progress uses a labelled list with the current step exposed through `aria-current`.
- All actions are real buttons. Launch at Login uses the foundation switch. API-key fields expose labels.
- Disabled navigation matches the native completion gates.

## 6. Review record

- Decision: expose current onboarding structure and representative visual states through one deterministic root composition.
- Authority: native files listed above.
- Checked: package typecheck, workspace check/build, and browser evidence are recorded with VOY-725 handoff.
- Unknown/deviation: dynamic material pixels, intrinsic control rendering, permission probes, provider verification, OAuth, and main-window opening are not executed.
- Follow-up: capture named native fixtures only when a pixel-level material or interaction parity claim is required.

## 7. Catalog ownership

The active registry entry is `surface-registry.ts` id `onboarding`. Stories live under the app-owned `src/Onboarding/` root, never beside package source.
