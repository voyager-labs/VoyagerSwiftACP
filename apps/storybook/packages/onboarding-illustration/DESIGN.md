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
- Base spacing unit is 4px. Native measurements are preserved where declared: 24px outer inset, 12px main gap, 40px top bar, 12px card inset, 12px corner radius, 8px progress dots. The shell top padding is 38px: the native 26px top inset plus 12px clearance for the browser-rendered traffic lights that native owns outside the content view.
- Button translation follows native push-button geometry: 6px corner radius, medium label weight compensating web antialiased smoothing, and a darkened accent edge on prominent fills. The Back control translates native `.buttonStyle(.plain)` and keeps primary label color at rest.

## 3. Reusable primitives

- `Button`: Back, Next, Complete, Retry, permission, and provider actions.
- `TextField`: API-key rows.
- `Toggle`: Launch at Login.
- `TrafficLights`: browser translation of native window chrome.
- `OnboardingWindow`: root workflow composition.
- `PermissionsStep` and `AiProviderStep`: reusable step specimens with app-owned component stories.
- `CompleteStep`: root-owned completion feedback; its compact phases stay in the window state matrix.

## 4. Deterministic states

The root window stories cover the full flow. Step stories separately expose blocked/granted/requesting Permissions and AI loading/error/mixed provider states without duplicating fixtures. Complete idle/opening/error remains root-owned. Fixtures contain no network, clock, random data, credentials, reducer execution, or OS permission probes.

## 5. Accessibility

- The window is a labelled region; progress uses a labelled list with the current step exposed through `aria-current`.
- All actions are real buttons. Accent actions use a dark system label for readable contrast. Launch at Login uses the foundation switch. API-key fields expose labels.
- Independent step specimens provide a level-one context heading while preserving native heading levels inside each component.
- Disabled navigation matches the native completion gates.
- Known contrast exception: the disabled primary label uses the quaternary label token (light ≈ 2.6:1), matching native disabled-control dimming; axe marks these translucent-material nodes as manual-review rather than violations.
- Per-provider Connect/Retry actions keep the accent primary fill because native `AiProviderSetupStepView` also styles them `.borderedProminent`; content-area prominence competing with the topbar CTA is native behavior, not a translation defect.
- Korean glyph rendering was verified in-browser through the SF font stack fallback (summary, subtitle, and button labels render without tofu or clipping); fixtures remain English-only by design.

## 6. Review record

- Decision: expose the full workflow through one deterministic root composition and detailed Permissions/AI states through reusable step specimens.
- Authority: native files listed above.
- Checked: package typecheck, workspace check/build, and browser evidence are recorded with VOY-725 handoff.
- Unknown/deviation: dynamic material pixels, intrinsic control rendering, permission probes, provider verification, OAuth, and main-window opening are not executed.
- Follow-up: capture named native fixtures only when a pixel-level material or interaction parity claim is required.

## 7. Catalog ownership

The active registry entry is `surface-registry.ts` id `onboarding`. Root workflow stories live under `src/Onboarding/Stories/`; reusable step specimens live under `src/Onboarding/Steps/`. Both remain app-owned and never live beside package source.
