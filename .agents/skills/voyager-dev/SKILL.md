---
name: voyager-dev
description: Unified Voyager(macOS) workflow for TCA + FSD implementation and test verification. Use this whenever working in `apps/macos/**` to scaffold or refactor TCA/FSD code, choose and run Voyager/macOS/SPM tests, analyze test failures, split reducers, move observation into reducers, evaluate reuse candidates, or enforce layer/public-boundary rules, even if the user does not explicitly mention `voyager-dev`.
compatibility: opencode
metadata:
    area: macos
    pattern: voyager-dev-tca-fsd
---

Use this skill for Voyager macOS TCA/FSD work.

## Trigger

- Any non-trivial Voyager macOS work under `apps/macos/Voyager/**`, `apps/macos/Packages/**`, or `apps/macos/Hosts/**`.
- Add a new Voyager module with TCA + FSD structure.
- Refactor a large feature into parent orchestrator + child reducers.
- Migrate nested `State`/`Action` to `Model/*` split files.
- Move view-owned external/system observation into reducer-owned TCA lifecycle.
- Run, select, or fix Voyager/macOS/SPM tests after code changes.
- Before implementation, find reusable symbols and enforce clean architecture gates.

## Workflow

1. Classify the task shape before editing.
    - `scaffold`: new module or feature shell.
    - `decompose`: large reducer/feature split or ownership cleanup.
    - `observation-refactor`: view-owned external/system observation.
    - `reuse-guard`: reuse/discovery question or duplication risk.
2. Load only the references needed for the task shape from the reference map below.
3. Always apply common guidance from:
    - `references/development-rules.md`
    - `references/tca-contract.md`
    - `references/verification.md`
4. Load every relevant playbook, not just one, when the change spans multiple task shapes.
5. Emit the task-shape deliverable described below.
6. Escalate to architecture, boundary, or testing references only when the task actually changes those concerns.
7. Execute checks from `references/verification.md`.
8. For Xcode project listing, build, or test execution, prefer `references/xcodebuildmcp-workflow.md` over raw `xcodebuild` CLI instructions.
9. When a task changes `State`/`Action`/reducer ownership, apply the action-taxonomy and reducer-composition heuristics from `references/development-rules.md` before choosing a split.
10. For test-only or test-fix work, route directly through `references/testing-playbook.md` and `references/verification.md`; this skill owns the Voyager test execution loop.

This skill routes internally. Do not ask the user to pick a mode.

## Reference map

- Always
    - `references/development-rules.md`
    - `references/tca-contract.md`
    - `references/verification.md`
- Any task needing Xcode project listing, build, or test execution
    - `references/xcodebuildmcp-workflow.md`
- `scaffold`
    - `references/layer-and-segment-rules.md`
    - `references/public-boundary-spec.md`
    - `references/package-extraction-posture.md`
        - `references/scaffold-spec.md`
    - Add `references/app-thin-integration-spec.md` when the task involves package-to-app wiring after extraction.
- `decompose`
    - `references/orchestrator-spec.md`
    - Add `references/testing-playbook.md` when routing, ownership, or reducer tests change.
    - Add `references/layer-and-segment-rules.md` and `references/public-boundary-spec.md` when the split changes layer, segment, or slice boundary.
- `observation-refactor`
    - `references/observation-lifecycle-spec.md`
    - Add `references/testing-playbook.md` when lifecycle, cancellation, or reducer tests change.
    - Add `references/layer-and-segment-rules.md` only when files move across `Ui` / `Lib` / `Api` / `Reducer`.
- `reuse-guard`
    - `references/layer-and-segment-rules.md`
    - `references/public-boundary-spec.md`
    - Add `references/package-extraction-posture.md` when the decision affects future package boundaries or shared extraction.
    - `references/testing-playbook.md`
    - `references/reuse-discovery-spec.md`
    - `references/architecture-gate-spec.md`
    - `references/decision-matrix.md`
    - Add `references/app-thin-integration-spec.md` when the task involves package-to-app wiring after extraction.
    - Add `references/shell-freeze-and-shared-promotion.md` when the task involves shared utility promotion or shell freeze.

Do not read every reference blindly. Start with the always-on references, then add only the playbooks that match the task. Use `references/macos-architecture-shape.md` as a navigation page only when you need help choosing the next deeper architecture reference. Use `references/xcodebuildmcp-workflow.md` only when the task requires actual Xcode project introspection, build, or test execution.

## Deliverable

- `scaffold`
    - Emit the chosen layer, slice boundary, segments to create, and the file list to add or modify.
    - Call out any omitted segments deliberately, especially when avoiding `Widgets/Api`.
    - Finish with verification and formatting commands.
- `decompose`
    - Emit the parent/child reducer split, action boundary, cancellation ownership, and touched files.
    - Finish with focused test targets and any follow-up cleanup search.
- `observation-refactor`
    - Emit the view cleanup, reducer lifecycle actions, observation owner, cancellation ID, and proof-search queries.
    - Finish with focused tests covering lifecycle and semantic routed actions.
- `reuse-guard`
    - Emit the ranked candidate table, architecture gate result, final choice (`reuse` | `adapt` | `new`), and implementation delta.
    - Record rejected candidates and the gate or score that disqualified them.

## Not for

- Trivial copy-only or spacing-only SwiftUI tweaks with no TCA, dependency, or architecture impact.
- Non-Voyager macOS work outside `apps/macos/Voyager/**`, `apps/macos/Packages/**`, or `apps/macos/Hosts/**` unless the task still clearly matches this skill's TCA/FSD workflow.
- Non-Voyager test execution outside `apps/macos/**` unless the task still depends on Voyager/macOS package context.

## Hard constraints

- Keep non-trivial `State`/`Action` in `Model/`.
- Keep orchestration in `Reducer/*Feature.swift`.
- Avoid splitting TCA core types through `State+*`, `Action+*`, `Feature+*`, or `Reducer+*` files when that spread starts to hide state movement and ownership.
- If a flow grows too large, extract dedicated model types, helper/coordinator types, or child features/reducers and compose them explicitly from the parent.
- Do not force one action taxonomy on every feature; prefer `view` / `internal` / `delegate` for UI-facing features and allow domain-family nested actions for operation/orchestration hubs when that better matches reducer ownership.
- Choose `Scope` for real child boundaries with dedicated substate/action, and prefer reducer-module composition when multiple concerns still share the same parent state/action.
- UI adapters (SwiftUI views, representables, coordinators) emit only `Action.view`/`@ViewAction` actions for the feature store they are initialized with.
- In UIKit/AppKit coordinators, react to feature state via TCA `observe { ... }`, not `store.publisher`/`sink`.
- Do not introduce Combine-based state subscriptions in coordinators.
- Keep external calls behind dependency clients.
- Accumulate Voyager-specific reusable heuristics in `references/development-rules.md` before promoting them into `.agents/rules/**`.
