# Voyager Storybook — Component Architecture and Design Review Rules

This file contains path-scoped review instructions for `apps/storybook/**`.

Review Voyager Storybook as a repository-aware frontend engineer. Evaluate
component architecture and rendered product quality together. Prefer existing
Storybook and package-local patterns; use general React and Storybook guidance
only when the repository has no relevant precedent.

## Review priorities

Prioritize these checks over generic frontend advice:

1. Does state live with the component that canonically owns the behavior?
2. Are render, fixture, orchestration, and story responsibilities separated
   enough that a change has one predictable owner?
3. Does the change reuse an existing component or style primitive instead of
   creating a divergent near-duplicate?
4. Do props express valid UI states without exposing incidental implementation
   details or allowing contradictory combinations?
5. Does the rendered result preserve hierarchy, spacing rhythm, balance,
   legibility, baseline identity, and the intended interaction model?
6. Can users operate real interactive controls, and does any declared
   accessibility state (`aria-pressed`, `aria-expanded`, `aria-selected`,
   `aria-label`) match the rendered visual state? Accessibility attributes are
   reviewed as a behavior contract — the attribute, the visible state, and the
   interaction must agree — not as a checklist of "must have" labels.

Do not use line count as a component-splitting rule. Flag size or decomposition
only when mixed responsibilities create concrete ownership, reuse, testing, or
change-isolation risk.

## Architecture findings

Treat an architecture issue as P1 when evidence shows one of these risks:

- State ownership is split so the same interface can enter conflicting states.
- A lower-level visual component owns story, page, or application orchestration.
- Render logic, fixtures, and interaction state are coupled so one concern cannot
  change without unrelated edits or duplicated setup.
- A new component bypasses an identified reusable local primitive and creates
  behavior or styling that can drift independently.
- Props expose internal mechanics, require callers to coordinate dependent flags,
  or admit combinations the component cannot render coherently.
- A dependency direction makes a reusable component depend on a concrete story
  or higher-level composition.

Cite the local component, hook, style primitive, or composition pattern that
demonstrates the issue. Do not request speculative abstraction without an
identified second use or a concrete ownership problem.

## Visual and interaction findings

Treat a visual or interaction issue as P1 when it has clear user impact:

- Content clips, overflows, overlaps, becomes unreadable, or loses essential
  information hierarchy at the story's intended viewport or minimum supported
  container width.
- Light/dark appearance or macOS visual baselines are mixed within one rendered
  surface in a way that breaks the selected design intent.
- Contrast, focus visibility, keyboard operation, semantics, or reduced-motion
  behavior prevents or materially impairs interaction.
- The result materially diverges from an explicit screenshot, macOS baseline,
  established token usage, or the PR's stated visual intent.
- Spacing, balance, or visual rhythm is degraded enough to obscure grouping,
  priority, or interaction affordance.

Accessibility findings are P1 only when a declared state or missing name
causes real user impact:

- A declared state attribute (`aria-pressed`, `aria-expanded`, `aria-selected`)
  has **no matching visible selected/expanded style**, so screen-reader and
  sighted users disagree about the current state. This is a defect even when the
  DOM is correct, because the visible state and the semantics diverge.
- A control that has **no visible text** (icon-only button) exposes no
  accessible name at all, so assistive technology cannot identify it.
- Contrast, focus visibility, keyboard operation, or reduced-motion behavior
  prevents or materially impairs interaction in the rendered story.

Do NOT raise P1/P2 for these — they add noise without user impact:

- Adding or demanding `aria-label` on a control whose visible text already
  provides the accessible name (duplicate/redundant label).
- Requiring an accessibility attribute purely because a similar control has one,
  without an identified interaction or state gap.
- Speculative assistive-technology behavior not confirmed against the rendered
  DOM or an actual screen-reader/interaction trace.
- A single deprecated or imperfectly-worded attribute that does not change the
  resolved accessible name or current state.

Source evidence is valid when the result is deterministic from the code, such as
a CSS cascade, selector match, token override, fixed overflow rule, or impossible
prop/state combination. Do not turn subjective preference into a blocking finding.

## Storybook-only P2 design polish

P2 is allowed only for files routed through this Storybook rule. Use it when the
interface remains functional and coherent but a concrete improvement would raise
spacing rhythm, balance, consistency, or finish. Exclude naming nits, arbitrary
taste, generic requests to "make it cleaner," and suggestions without a specific
location and direction.

Do not emit individual inline P2 comments. Deduplicate them and place them in one
review-footer section:

```text
Design polish
- [P2] `<path>`: <observable issue> — <specific direction>
```

Keep P0/P1 findings in the repository's standard finding format.

## Evidence and rendered review

For changes that can alter rendering, approval requires using the built Storybook
in a real browser and checking representative changed stories. Cover the intended
viewport and the component's minimum supported width rather than imposing generic
mobile breakpoints on macOS illustrations. Exercise the changed happy path and a
relevant edge or interaction state when one exists.

A source-proven finding may still be reported, but the final verdict must include
the rendered review result. Record the story, viewport or container condition,
and observed behavior. Drop visual findings that remain speculative after the
available source and browser evidence are considered.

For accessibility findings, confirm the attribute against the rendered DOM and
verify the visible counterpart before leaving a comment. A `aria-pressed`/`aria-expanded`
claim must show both the attribute and the matching rendered style; an `aria-label`
claim must show the control's visible text (or absence of it) in the built story.

Generated output may be used as evidence but is not the repair owner. Trace a
generated CSS or metadata defect to its generator or input source and leave the
finding there. If the owning source is outside the PR diff, describe that scope
fact rather than requesting a manual edit to generated output.

## Explicit exclusions

Do not review these concerns under this rule:

- Package export maps, public API compatibility, catalog counts, or generated
  contract parity.
- Whether a component or visual state has a dedicated story.
- Formatting, import ordering, obvious type errors, or build failures that CI
  reports directly.
- Generated files excluded by `.pr-review/config.yaml` as direct repair targets.
- Mobile/tablet layouts that the story and component do not claim to support.

Do not duplicate a CI failure as a review comment unless the diff also contains a
separate architecture or rendered-design defect covered above.
