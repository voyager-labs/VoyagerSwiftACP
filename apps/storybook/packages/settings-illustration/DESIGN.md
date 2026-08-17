# Settings Illustration Design System

This document records the native-parity **TabView** design of the Settings illustration (General / Appearance / AI). Storybook is an inspectable review surface for the design lab, not product or native-runtime truth. The earlier sidebar idiom (General + Paths) is retired; see the Follow-up record for the VOY-191 Paths removal.

## 1. Authority

The illustration mirrors the native macOS Settings window, which is a `TabView` with a fixed `600×400` frame and tab items derived from `SettingsSection.visibleCases`.

- **`SettingsView.swift:11-35`** — `TabView(selection:)`, `.frame(width: 600, height: 400)`, tab items via `.tabItem { Label(section.title, systemImage: section.iconName) }`, and the command-W close-window hidden background button.
- **Visible tabs** from `SettingsTypes.swift:4-42` — `SettingsSection` enum with `general`, `appearance`, `ai`, `account`; `visibleCases` filters out `.account` (`SettingsTypes.swift:10-12`), so the rendered tabs are **General / Appearance / AI**. Titles and icon names come from the same enum (`SettingsTypes.swift:18-42`): `gear`, `paintbrush`, `sparkle`.
- **Per-tab authority** (file:line):
    - `GeneralSettingsView.swift` — General tab: launch-at-startup / alert-before-quit toggles, Updates section, Workspace starting-directory menu, Default File Viewer section.
    - `AppearanceSettingsView.swift` — Appearance tab: Theme cards, Show Hidden Files toggle, View size presets, Customize per view disclosure.
    - `AiSettingsView.swift` — AI tab: AI Connections rows, Default Chat and Collection Search model-settings disclosure groups.
    - `AiConnectionRowView.swift` — the AI connection rows rendered inside the AI tab (`AiSettingsView.swift:68-70` iterates rows with `AiConnectionRowView(store:)`); native source lives at `apps/macos/Packages/04_Features/AiProviderConnection/Sources/VoyagerFeaturesAiProviderConnection/Ui/AiConnectionRowView.swift`.
- **Canonical contract** — SET-001 `settings_window.toolbar.tabs_area` owns the toolbar-tab strip. It is the contract authority for the top tab bar; the tab strip is a translation default (see Translation notes), not a native measurement.

## 2. Translation notes

- **Translation defaults, not native measurements.** The toolbar-tab strip ≈37px, section content insets 16px, rows 10px vertical padding, and section corner radius 8px are **translation defaults** (natively unspecified). The native `TabView` does not pin these values; Storybook chooses them so the web translation reads at native density. They must not be cited as native measurements.
- **SF Symbols** render through the `symbolist` package (name → Unicode glyph) using the bundled `/fonts/sf-pro/SF-Pro-Symbols.otf` assets; on macOS the browser falls back to the system `.SF Symbols` font. Icons go through the `SFSymbol` foundation component (`Foundations/SFSymbol.tsx`), not inline SVG.
- **Static presentation.** Fixtures are deterministic and local: no network, no clock, no random data, no simulated production backend. There is no live reducer and no reducer/business-logic execution. The only interaction is tab switching (see Decision record); pickers, menus, toggles, and disclosure groups are non-interactive deterministic fixtures.
- **Token mapping.** Grouped-form (card) section background maps `controlBackgroundColor` through `--set-form-bg`, which is an alias of a `--macos-*` background token (`--set-form-bg: var(--macos-control-background-color)` in `styles/settings.css`). AI connection status dots map through `--set-status-connected` and `--set-status-not-connected` (aliases of `--macos-system-green` and `--macos-tertiary-label-color`). No component-level raw colors are used.
- **The only raw-color exceptions** are the three Appearance theme-preview colors (`rgb(102,153,230)` and `rgb(51,77,128)`, plus the auto split), cited to `AppearanceSettingsView.swift:24-28,55-59`. These are native-derived reference values, documented inline in `styles/appearance-pane.css`, and are the sole exception to the token-only color rule.

## 3. Decision record

### Checked

- Typecheck passes (`tsc -b`), `pnpm check`, and `build-storybook` succeed with both surfaces present in `index.json`.
- `agent-browser` evidence captured on all 6 stories (`Default`, `AppearanceTab`, `AiTab`, `AiTabConnected`, `AppearanceCustomizeExpanded`, `AiModelSettingsExpanded`).
- Tab-switching interaction proven: the top tab bar switches General / Appearance / AI panes in a real browser session.

### Unknown / deviation

- **Static presentation** — no mutation, no live provider data, no real auth/network. Pickers, menus, toggles, and disclosure groups are non-interactive deterministic fixtures. This is **visual/reference parity only**, NOT native-runtime proof or runtime equivalence. A clickable control proves only the web prototype unless an executable test proves more.
- Native dynamic behavior (provider connection, model catalogs, error states, system restart requirements) is represented only by fixture-driven visual states, not by executing the underlying logic.

### Follow-up

- **VOY-191 Paths pane REMOVED 2026-08-17** per product decision. The sidebar's per-path-preference preview (`PathPreferenceRule` table) was not present in the native app, which uses the TabView idiom instead. The Paths pane is not part of this design; it returns as candidate stories when the native Paths feature ships.
- **Account / Shortcuts tabs out of scope** — the native `visibleCases` excludes `.account`, so Storybook does not render an Account tab or claim one.

## 4. Catalog Taxonomy

- **Foundations** — `SFSymbol` is a product-agnostic visual primitive for SF Symbol glyphs; it owns no Settings workflow state.
- **Layouts** — `GeneralSettingsPane`, `AppearanceSettingsPane`, `AiSettingsPane` own pane geometry and composition within the tab content area, plus their section rows.
- **Root** — `SettingsWindow` is the root composition owning the titlebar, the top tab bar, and the active pane. It is presentational and deterministic: fixture-driven, no live reducer, no real event handlers beyond tab switching.
- **Domains** — AI connection rows belong to the AI pane's domain; provider/auth/status are fixture data only.

## 5. Spacing & Layout

- Base spacing unit: 4px, via the `--set-*` geometry scale.
- Default window: 780px wide × 520px tall (illustration stage, not the native 600×400 `TabView` frame; the illustration renders at a larger review scale while keeping the native proportion).
- Titlebar: 52px tall with traffic-light controls.
- Top tab strip: ≈37px (translation default) with a bottom hairline separator and a 3px active-tab accent indicator.
- Tab content pane: 16px inset (translation default), card sections at 8px corner radius with 10px vertical row padding (translation defaults).
- All colors come from `--macos-*` tokens or their `--set-*` aliases, so contrast is maintained across light/dark schemes.

## 6. Accessibility

- Target WCAG 2.2 AA semantics: the tab bar is a `<nav aria-label="Settings categories">` with real `<button>` tab items exposing `aria-current="page"` on the active tab; the window is a `<section aria-label="Voyager Settings">`.
- Toggles are real `<button role="switch" aria-checked>`; the theme cards and disclosure rows are real interactive elements where the review surface needs it.
- Icons render through `SFSymbol` with `aria-hidden="true"` on their owning controls; no visible emoji icons.
- Browser verification: after every visual change, drive a real browser (`agent-browser`) to capture and inspect the affected states. Screenshot evidence is required before declaring a visual task complete.

## 7. Not in scope

- This is not a native-runtime architecture. No AppKit bridge, no runtime provider data, no real auth/network, and no CI-side capture. The illustration is a static review translation that demonstrates native-parity structure and presentation only.
