# VOY-231 AiChat Orchestration

## TL;DR

> **Summary**: Implement VOY-231 as one strict wave-gated orchestration: reusable `Entities/Ai` contracts, standalone `04_Features/AiChat`, thin FileManager host/context adapter, then issue-level integration verification. Core chat behavior must be proven in `AiChat` reducer/package tests before app integration.
> **Deliverables**:
>
> - `VoyagerEntitiesAi` reusable chat/request/model/session DTOs and client contracts only
> - New `VoyagerFeaturesAiChat` package owning chat state machine, UI, dependency clients, reducer tests
> - FileManager content host wiring and pure context adapter
> - Wave gates and AC evidence for VOY-237, VOY-238, VOY-219, VOY-222
>   **Effort**: Medium
>   **Parallel**: YES - limited, wave-gated only
>   **Critical Path**: Wave 0 contract gate → Wave 1 entity contracts → Wave 2 standalone AiChat behavior → Wave 3 FileManager host → Wave 4 integration verification

## Context

### Original Request

- Plan Phase 2 of the BYOK/subscription-linked AI chat project in `phase/voy-231`.
- Cover VOY-231 and child issues:
    - VOY-237: current-context external AI chat entry/basic screen
    - VOY-238: current chat provider/model display and model change
    - VOY-219: external AI request execution and response handling
    - VOY-222: conversation session continuity and context delivery
- Prefer one orchestration plan/run, with issue-level AC strengthened before execution.

### Interview Summary

- User rejected an Inspector-owned approach; Inspector may be a surface but must not own chat orchestration.
- Decision: create reusable `04_Features/AiChat`; keep FileManager as thin host/context adapter; keep `05_Entities/Ai` as provider/auth/contract foundation.
- Decision: one Sisyphus plan is acceptable only with strict wave gates and stop conditions.

### Metis Review (gaps addressed)

- Added immutable STOP conditions to Wave 0.
- Added `Entities/Ai` allowlist/denylist.
- Added `AiChat` public-boundary audit.
- Moved core behavior proof into `AiChat` reducer/package tests instead of Wave 4.
- Added app-layer streaming/cancellation invariants and request/run ID correlation.
- Added session restore/rebind edge cases and regenerate semantics.

### Oracle Review (gaps addressed)

- Conditional GO for one wave-gated plan.
- Added session persistence/rebind/restore failure contract to Wave 1~2.
- Added final transcript exactly-once persistence to Wave 2 required AC.
- Kept Wave 4 as integration verification only.

## Work Objectives

### Core Objective

Deliver a first usable current-context external AI chat slice where FileManager can open an AI chat surface, pass current context to a reusable AiChat feature, show/change the active model for the next request, execute/stream responses through existing BYOK/Codex/API-key connection groundwork, and maintain minimum session/context continuity.

### Deliverables

- New package: `apps/macos/Packages/04_Features/AiChat/`
- Entity contract extensions in `apps/macos/Packages/05_Entities/Ai/`
- FileManager host/adapter integration under `apps/macos/Voyager/Voyager/02_Pages/FileManager/Content/`
- Focused package/reducer/app tests and evidence files under `.sisyphus/evidence/`

### Definition of Done

- `xcrun swift test --package-path apps/macos/Packages/05_Entities/Ai` passes.
- `xcrun swift test --package-path apps/macos/Packages/04_Features/AiChat` passes.
- Focused FileManager tests pass via `xcodebuild test -scheme Voyager-Dev -project apps/macos/Voyager/Voyager.xcodeproj -only-testing:VoyagerTests/Pages/FileManager` or the exact focused suite discovered by the executor.
- Boundary search proves no `FileManager`, `Pages`, or `Voyager` app imports inside `apps/macos/Packages/04_Features/AiChat` and no upward imports in `apps/macos/Packages/05_Entities/Ai`.
- VOY-237/238/219/222 AC checklist is mapped to passing tests/evidence.

### Must Have

- `request_context_locked` at submit/regenerate time.
- Model changes apply to the next request only, not in-flight requests.
- Cancel/superseded request events cannot mutate UI/transcript/session state.
- Partial stream deltas are UI-only drafts; final transcript persists exactly once from final response/onFinish.
- Restore failed / rebind required / no existing record fall back to `new_session` for MVP.
- FileManager adapts context and hosts UI only.

### Must NOT Have

- No MCP, tools, file execution, background agents, autonomous workflow, long-term memory, multi-provider routing/fallback engine, automatic model recommendation, advanced provider parameter UI, model benchmarking, pricing UI, or token estimation.
- No FileManager/Page imports in `AiChat`.
- No `AiChat`, FileManager, SwiftUI UI state, TCA reducer/action/effect, cancellation IDs, concrete SDK execution, transcript mutation policy, or session orchestration inside `Entities/Ai`.
- No persisted partial streaming deltas.
- No Wave 4-first proof of core behavior.

## Verification Strategy

> ZERO HUMAN INTERVENTION - all verification is agent-executed.

- Test decision: tests-after with reducer-first TCA `TestStore` coverage and package tests.
- QA policy: Every task has agent-executed scenarios.
- Evidence: `.sisyphus/evidence/task-{N}-{slug}.{ext}`.
- Preferred commands:
    - `xcrun swift test --package-path apps/macos/Packages/05_Entities/Ai --filter '...'`
    - `xcrun swift test --package-path apps/macos/Packages/04_Features/AiChat --filter '...'`
    - `xcodebuild test -scheme Voyager-Dev -project apps/macos/Voyager/Voyager.xcodeproj -only-testing:VoyagerTests/Pages/FileManager`
    - `swiftlint --config apps/macos/Voyager/.swiftlint.yml --reporter xcode`
    - `swiftformat --config apps/macos/Voyager/.swiftformat apps/macos/Voyager --verbose`

## Execution Strategy

### Parallel Execution Waves

> Target: strict wave gates. Do not start later waves until earlier wave gate is green.

- Wave 0: immutable contract and AC traceability
- Wave 1: `VoyagerEntitiesAi` reusable contracts only
- Wave 2: standalone `VoyagerFeaturesAiChat` package and behavior tests
- Wave 3: FileManager thin host/context adapter
- Wave 4: issue-level and integration verification

### Dependency Matrix

- T1 blocks all implementation tasks.
- T2 blocks T3, T4, T5.
- T3 blocks T6, T7, T8.
- T4 and T5 block T6.
- T6 blocks T7 and T8.
- T7 and T8 block final verification.

### Agent Dispatch Summary

- Wave 0: 1 deep/planning task
- Wave 1: 1 quick/deep Swift package task
- Wave 2: 3 feature tasks, mostly serial due shared reducer state machine
- Wave 3: 1 FileManager integration task
- Wave 4: 4 parallel review/QA agents

## TODOs

> Implementation + Test = ONE task. Never separate.
> EVERY task MUST have: Agent Profile + Parallelization + QA Scenarios.

- [x]   1. Wave 0: Freeze VOY-231 hard contract and issue AC traceability

    **What to do**: Create implementation-facing contract notes inside the plan/evidence flow before code changes. Map VOY-237/238/219/222 to CBW contracts and define stop conditions: upward imports, FileManager owning chat semantics, partial persistence, cancel late chunks, in-flight model mutation, missing reducer AC tests. If executor finds CBW/code/SDK facts contradict this plan, stop and update plan before implementation.
    **Must NOT do**: Do not edit product docs or change source code in this task.

    **Recommended Agent Profile**:
    - Category: `deep` - Reason: cross-issue contract synthesis and stop-condition enforcement.
    - Skills: [`voyager-dev`] - required for Voyager FSD/TCA boundaries.
    - Omitted: [`frontend-ui-ux`] - not designing visuals here.

    **Parallelization**: Can Parallel: NO | Wave 0 | Blocks: T2-T8 | Blocked By: none

    **References**:
    - Linear: VOY-231, VOY-237, VOY-238, VOY-219, VOY-222, VOY-235.
    - Spec: `docs/canonical/PRODUCT/05_FEATURE_SPECS/cbw/flows/contextual_chat_request_flow.md` - request/session/model combination.
    - Spec: `docs/canonical/PRODUCT/05_FEATURE_SPECS/cbw/flows/request_context_management_flow.md` - request context snapshot locking.
    - Spec: `docs/canonical/PRODUCT/05_FEATURE_SPECS/cbw/flows/chat_provider_model_selection_flow.md` - model-centric next-request semantics.
    - Spec: `docs/canonical/PRODUCT/05_FEATURE_SPECS/cbw/flows/chat_session_restore_flow.md` - new_session fallback.
    - Rules: `.agents/skills/voyager-dev/references/layer-and-segment-rules.md` - FSD direction.
    - Rules: `.agents/skills/voyager-dev/references/tca-contract.md` - TCA ownership/cancellation rules.

    **Acceptance Criteria**:
    - [ ] Evidence file lists issue-to-wave mapping for VOY-237/238/219/222.
    - [ ] Evidence file lists `Entities/Ai` allowlist and denylist.
    - [ ] Evidence file lists `AiChat` public boundary and FileManager host-only contract.
    - [ ] Evidence file lists reducer-level AC that must be proven before Wave 4.

    **QA Scenarios**:

    ```
    Scenario: Contract traceability complete
      Tool: Bash
      Steps: Verify `.sisyphus/evidence/task-1-contract.md` exists and contains VOY-237, VOY-238, VOY-219, VOY-222, request_context_locked, next-request-only, final transcript exactly-once, and new_session fallback.
      Expected: All required terms are present exactly in evidence.
      Evidence: .sisyphus/evidence/task-1-contract.md

    Scenario: Stop condition present
      Tool: Bash
      Steps: Verify evidence contains STOP conditions for upward imports, FileManager chat ownership, partial persistence, cancel late chunks, in-flight model mutation.
      Expected: Missing any STOP condition fails the task.
      Evidence: .sisyphus/evidence/task-1-contract-stop.md
    ```

    **Commit**: NO | Message: n/a | Files: `.sisyphus/evidence/task-1-*` are local-only agent evidence and must not be staged or committed.

- [x]   2. Wave 1: Add `VoyagerEntitiesAi` reusable chat contracts only

    **What to do**: Extend `apps/macos/Packages/05_Entities/Ai` with reusable public/internal types needed by `AiChat`: provider/model handles, model catalog row metadata, request context snapshot DTO, chat session ID/status, request/run ID, chat request/response/event DTO, execution/session persistence client protocols as contracts. Add tests for Codable/Equatable/Sendable behavior and ensure existing Settings-facing provider/auth APIs remain compatible.
    **Must NOT do**: No SwiftUI, no TCA reducer/action/effect, no concrete Swift AI SDK execution, no FileManager/Page imports, no session orchestration policy, no cancellation IDs.

    **Recommended Agent Profile**:
    - Category: `deep` - Reason: package boundary and public API stability.
    - Skills: [`voyager-dev`] - package/FSD/testing rules.
    - Omitted: [`frontend-ui-ux`] - no UI.

    **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: T3-T8 | Blocked By: T1

    **References**:
    - Pattern: `apps/macos/Packages/05_Entities/Ai/Package.swift` - current package/test target.
    - Pattern: `apps/macos/Packages/05_Entities/Ai/Sources/VoyagerEntitiesAi/Model/AIProvider.swift` - provider descriptor style.
    - Pattern: `apps/macos/Packages/05_Entities/Ai/Sources/VoyagerEntitiesAi/Api/AIProviderConnectionClient.swift` - client protocol/dependency style.
    - Pattern: `apps/macos/Packages/05_Entities/Ai/Tests/VoyagerEntitiesAiTests/*` - package test style.

    **Acceptance Criteria**:
    - [ ] `VoyagerEntitiesAi` tests pass.
    - [ ] New DTOs are independent of FileManager/Page/App types.
    - [ ] Search proves no `import Voyager`, `FileManager`, `Pages`, or `VoyagerFeaturesAiChat` appears in `apps/macos/Packages/05_Entities/Ai/Sources`.
    - [ ] Existing `VoyagerPagesSettings` usage remains source-compatible.

    **QA Scenarios**:

    ```
    Scenario: Entity contract tests pass
      Tool: Bash
      Steps: Run `xcrun swift test --package-path apps/macos/Packages/05_Entities/Ai --filter 'AiChat|Chat|Session|Model|Request|ProviderConnectionState|AiLiveValue'`.
      Expected: Command exits 0.
      Evidence: .sisyphus/evidence/task-2-entities-tests.txt

    Scenario: Entity boundary has no upward imports
      Tool: Bash
      Steps: Search `apps/macos/Packages/05_Entities/Ai/Sources` for `FileManager|VoyagerFeaturesAiChat|02_Pages|04_Features|import Voyager`.
      Expected: No matches except literal comments in evidence if any; source files must have none.
      Evidence: .sisyphus/evidence/task-2-entities-boundary.txt
    ```

    **Commit**: YES | Message: `feat(ai): add chat contract types`

- [x]   3. Wave 2a: Scaffold standalone `VoyagerFeaturesAiChat` package

    **What to do**: Create `apps/macos/Packages/04_Features/AiChat/` following `BetaAccess` package shape. Include `Package.swift`, module entry file, `Model/AiChatState.swift`, `Model/AiChatAction.swift`, `Reducer/AiChatFeature.swift`, `Ui/AiChatView.swift`, `Api/AiChatExecutionClient.swift` if execution boundary belongs in feature, and a test target. Wire dependencies only downward to `VoyagerEntitiesAi` and `VoyagerShared` as needed.
    **Must NOT do**: No FileManager imports, no app target dependencies, no broad public re-export.

    **Recommended Agent Profile**:
    - Category: `quick` - Reason: scaffold from existing package patterns.
    - Skills: [`voyager-dev`] - scaffold shape.
    - Omitted: [`git-master`] - no git operation requested.

    **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: T4-T8 | Blocked By: T2

    **References**:
    - Pattern: `apps/macos/Packages/04_Features/BetaAccess/Package.swift` - simple feature package.
    - Pattern: `apps/macos/Packages/04_Features/BetaAccess/Sources/VoyagerFeaturesBetaAccess/Model/BetaAccessState.swift` - state split.
    - Pattern: `apps/macos/Packages/04_Features/BetaAccess/Sources/VoyagerFeaturesBetaAccess/Reducer/BetaAccessFeature.swift` - reducer entry.
    - Rules: `.agents/skills/voyager-dev/references/scaffold-spec.md` - required file shape.

    **Acceptance Criteria**:
    - [ ] Package has `Model`, `Reducer`, `Ui`, `Api` only if needed, and Tests.
    - [ ] State is `@ObservableState` and `Equatable`; Action is `Sendable` and case-path-compatible if needed.
    - [ ] Package compiles/tests standalone.

    **QA Scenarios**:

    ```
    Scenario: AiChat package compiles standalone
      Tool: Bash
      Steps: Run `xcrun swift test --package-path apps/macos/Packages/04_Features/AiChat`.
      Expected: Command exits 0.
      Evidence: .sisyphus/evidence/task-3-aichat-scaffold-tests.txt

    Scenario: AiChat has no Page dependency
      Tool: Bash
      Steps: Search `apps/macos/Packages/04_Features/AiChat/Sources` for `FileManager|02_Pages|import Voyager`.
      Expected: No source matches.
      Evidence: .sisyphus/evidence/task-3-aichat-boundary.txt
    ```

    **Commit**: YES | Message: `feat(aichat): scaffold standalone feature package`

- [x]   4. Wave 2b: Implement VOY-237/238 AiChat entry, basic screen, model selection state

    **What to do**: In `AiChat`, implement initial chat surface state, current context summary display model, unconnected/error/empty/ready/processing states, input draft, cancel affordance state, active model catalog state, model-centric field label, same-model no-op, fallback to first catalog row when active model missing/unresolvable, and next-request-only selected model semantics. Add reducer and view tests.
    **Must NOT do**: No real provider execution, no session persistence store, no FileManager-specific context types, no provider routing/fallback engine.

    **Recommended Agent Profile**:
    - Category: `deep` - Reason: TCA state machine and AC-heavy reducer tests.
    - Skills: [`voyager-dev`] - reducer/testing rules.
    - Omitted: [`frontend-ui-ux`] - use existing design system/simple structure, not new visual direction.

    **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: T5-T8 | Blocked By: T3

    **References**:
    - Spec: `docs/canonical/PRODUCT/05_FEATURE_SPECS/cbw/flows/chat_provider_model_selection_flow.md` - model-centric selection.
    - Spec: `docs/canonical/PRODUCT/05_FEATURE_SPECS/cbw/contracts/model_selection_contract.toml` - first-row fallback and `model_selected`.
    - Linear: VOY-237 and VOY-238.

    **Acceptance Criteria**:
    - [ ] Current context summary is visible in empty/ready states.
    - [ ] Unconnected state exposes connection-fix action metadata but does not implement settings navigation inside feature.
    - [ ] Chat field shows model label; provider is passive catalog metadata.
    - [ ] Model change updates selected model for subsequent requests only.
    - [ ] Same model selection is no-op.

    **QA Scenarios**:

    ```
    Scenario: Entry opens ready chat with context summary
      Tool: Bash
      Steps: Run AiChat reducer tests filtering `Entry|ContextSummary|Unconnected`.
      Expected: Empty/ready/unconnected states match VOY-237 AC.
      Evidence: .sisyphus/evidence/task-4-entry-tests.txt

    Scenario: Model change applies next request only
      Tool: Bash
      Steps: Run AiChat reducer tests filtering `ModelSelection|NextRequest|NoOp`.
      Expected: In-flight request locked model is unchanged; next draft uses selected model; same selection no-ops.
      Evidence: .sisyphus/evidence/task-4-model-tests.txt
    ```

    **Commit**: YES | Message: `feat(aichat): add entry and model selection state`

- [x]   5. Wave 2c: Implement VOY-219 execution, streaming, cancellation, finalization in AiChat

    **What to do**: Implement feature-owned execution effect and dependency client boundary. On submit/regenerate, capture immutable request context and selected model into a request/run ID. Stream deltas into draft UI only. Commit final assistant message exactly once on final response for current non-cancelled request. Ignore late chunks/final events for cancelled or superseded request IDs. Implement processing/completed/failed/cancelled transitions, partial failure UI state, retry/regenerate metadata, and persistence-error recovery state.
    **Must NOT do**: Do not rely on SDK cancellation guarantees for correctness; do not persist partial deltas; do not duplicate user turns on regenerate.

    **Recommended Agent Profile**:
    - Category: `deep` - Reason: async effects, cancellation, transcript invariants.
    - Skills: [`voyager-dev`] - TCA effect/cancellation testing.
    - Omitted: [`security-review`] - no secrets/auth storage changes beyond existing clients; final review covers risk.

    **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: T6-T8 | Blocked By: T4

    **References**:
    - Spec: `docs/canonical/PRODUCT/05_FEATURE_SPECS/cbw/flows/contextual_chat_request_flow.md` - request execution composition.
    - Spec: `docs/canonical/PRODUCT/05_FEATURE_SPECS/cbw/CBW-001-manage-chat-request-lifecycle/CBW-001-show_request_processing_state.md` - states and late chunk guard.
    - External: `https://swift-ai-sdk-docs.vercel.app/` - streaming/finalization constraints; cancellation not strongly guaranteed.

    **Acceptance Criteria**:
    - [ ] Submit/regenerate captures `request_context_locked` and model into request/run ID.
    - [ ] Processing/completed/failed/cancelled transitions are reducer-tested.
    - [ ] Cancel retires active request and late chunks/final events are ignored.
    - [ ] Partial deltas update draft UI only.
    - [ ] Final transcript persists exactly once for current non-cancelled request.
    - [ ] Regenerate creates no duplicate user turn and replaces assistant final for same turn; failed/cancelled regenerate preserves prior successful final unless spec says otherwise.

    **QA Scenarios**:

    ```
    Scenario: Streaming success finalizes exactly once
      Tool: Bash
      Steps: Run AiChat reducer tests filtering `Streaming|Finalization|ExactlyOnce`.
      Expected: Draft receives deltas; final assistant message is committed once; persistence called once.
      Evidence: .sisyphus/evidence/task-5-stream-finalization.txt

    Scenario: Cancel ignores late events
      Tool: Bash
      Steps: Run AiChat reducer tests filtering `Cancel|LateChunk|Superseded`.
      Expected: After cancel, late deltas/final response do not mutate draft, transcript, or session status.
      Evidence: .sisyphus/evidence/task-5-cancel-late-events.txt
    ```

    **Commit**: YES | Message: `feat(aichat): handle streaming request lifecycle`

- [x]   6. Wave 2d: Implement VOY-222 session continuity and restore/rebind fallback in AiChat

    **What to do**: Implement single active session semantics, session status display model, restore attempt input, restore_failed/rebind_required/no-record to `new_session` fallback, valid restore to `restored_session`, stale model/provider/auth handling, context mismatch guard, previous in-flight request normalization on restore, and transcript continuity/truncation boundary. Keep policy in `AiChat`, with `Entities/Ai` only providing DTO/contracts.
    **Must NOT do**: No long-term memory, cross-session memory, complex session strategy, or global session manager.

    **Recommended Agent Profile**:
    - Category: `deep` - Reason: state restoration and edge-case reducer coverage.
    - Skills: [`voyager-dev`] - TCA and lifecycle rules.
    - Omitted: [`ultrabrain`] - bounded domain, no need for heavyweight reasoning.

    **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: T7-T8 | Blocked By: T5

    **References**:
    - Spec: `docs/canonical/PRODUCT/05_FEATURE_SPECS/cbw/flows/chat_session_restore_flow.md` - restore/new_session flow.
    - Spec: `docs/canonical/PRODUCT/05_FEATURE_SPECS/cbw/contracts/chat_session_contract.toml` - status and fallback.
    - Linear: VOY-222.

    **Acceptance Criteria**:
    - [ ] Exactly one active session per chat surface.
    - [ ] No existing record starts `new_session` without error.
    - [ ] Invalid record/restore failure falls back to `new_session` and does not activate stale transcript.
    - [ ] Context mismatch records `rebind_required` then falls back to `new_session` for MVP.
    - [ ] Valid restore resumes transcript and status as `restored_session`.
    - [ ] Previous in-flight request on app close is normalized to non-processing state on restore.

    **QA Scenarios**:

    ```
    Scenario: Restore failure falls back to new session
      Tool: Bash
      Steps: Run AiChat reducer tests filtering `Restore|NewSession|Rebind`.
      Expected: Invalid/no/mismatched record does not activate stale session; MVP fallback is new_session.
      Evidence: .sisyphus/evidence/task-6-session-restore.txt

    Scenario: Valid restore preserves continuity
      Tool: Bash
      Steps: Run AiChat reducer tests filtering `SessionContinuity|Transcript|Restore`.
      Expected: Restored session has previous transcript, selected model handling, and next request includes turn history.
      Evidence: .sisyphus/evidence/task-6-session-continuity.txt
    ```

    **Commit**: YES | Message: `feat(aichat): maintain session continuity`

- [x]   7. Wave 3: Mount AiChat in FileManager as thin host and context adapter

    **What to do**: Add FileManager content presentation state/action/routing for AiChat. Mount `AiChatView` in `FileManagerContentPaneView` and add toolbar entry in `ToolbarView` first. Add `Content/Lib/FileManagerAiChatContextAdapter.swift` as a pure conversion from FileManager content/navigation state to `AiChat` context DTO. Add tests proving FileManager only opens/mounts/passes context and does not inspect/mutate request/session/model semantics.
    **Must NOT do**: Do not implement chat semantics in FileManager. Do not make InspectorPane the owner. Do not add context menu/key command until toolbar path is green unless explicitly scoped as a follow-up.

    **Recommended Agent Profile**:
    - Category: `deep` - Reason: app integration and boundary proof.
    - Skills: [`voyager-dev`] - FileManager/FSD/TCA integration.
    - Omitted: [`frontend-ui-ux`] - minimal host mount only.

    **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: T8 | Blocked By: T6

    **References**:
    - Host: `apps/macos/Voyager/Voyager/02_Pages/FileManager/Content/Model/FileManagerContentState.swift`
    - Host: `apps/macos/Voyager/Voyager/02_Pages/FileManager/Content/Model/FileManagerContentAction.swift`
    - Host: `apps/macos/Voyager/Voyager/02_Pages/FileManager/Content/Reducer/FileManagerContentFeature.swift`
    - Host: `apps/macos/Voyager/Voyager/02_Pages/FileManager/Content/Ui/FileManagerContentPaneView.swift`
    - Entry: `apps/macos/Voyager/Voyager/02_Pages/FileManager/Content/Ui/ToolbarView.swift`
    - Adapter: new `apps/macos/Voyager/Voyager/02_Pages/FileManager/Content/Lib/FileManagerAiChatContextAdapter.swift`

    **Acceptance Criteria**:
    - [ ] Toolbar entry opens AiChat surface with current context summary.
    - [ ] Adapter handles current view context, selected item context, empty/no selection context, and navigation/window identity if required.
    - [ ] FileManager tests assert host passes context snapshot and does not own chat semantics.
    - [ ] Search proves no chat request/session/model lifecycle code in FileManager beyond host/adapter translation.

    **QA Scenarios**:

    ```
    Scenario: Toolbar opens AiChat with adapted context
      Tool: Bash
      Steps: Run focused FileManager tests for AiChat host/mount/adapter.
      Expected: Toolbar action presents AiChat and sends adapted context DTO to feature.
      Evidence: .sisyphus/evidence/task-7-filemanager-host.txt

    Scenario: FileManager remains host-only
      Tool: Bash
      Steps: Search FileManager touched files for request lifecycle/session/model mutation symbols outside adapter/mount routing.
      Expected: No FileManager-owned chat semantics; only adapter/presentation routing.
      Evidence: .sisyphus/evidence/task-7-filemanager-boundary.txt
    ```

    **Commit**: YES | Message: `feat(filemanager): mount contextual ai chat`

- [x]   8. Wave 4: Run issue-level verification and boundary audit

    **What to do**: Produce final evidence mapping VOY-237/238/219/222 AC to passing tests and commands. Run package tests, focused FileManager tests, boundary import searches, and final smoke build/test as appropriate. If Wave 4 discovers behavior failure, reopen the owning earlier wave; do not patch semantics only in integration.
    **Must NOT do**: Do not use Wave 4 as first proof for core behavior.

    **Recommended Agent Profile**:
    - Category: `deep` - Reason: cross-package verification and evidence synthesis.
    - Skills: [`voyager-dev`] - verification workflow.
    - Omitted: [`git-master`] - commit strategy handled separately if requested.

    **Parallelization**: Can Parallel: YES | Wave 4 | Blocks: final verification | Blocked By: T7

    **References**:
    - Verification: `.agents/skills/voyager-dev/references/verification.md`
    - Testing: `.agents/skills/voyager-dev/references/testing-playbook.md`
    - Xcode: `.agents/skills/voyager-dev/references/xcodebuildmcp-workflow.md`

    **Acceptance Criteria**:
    - [ ] VOY-237 AC mapped to passing evidence.
    - [ ] VOY-238 AC mapped to passing evidence.
    - [ ] VOY-219 AC mapped to passing evidence.
    - [ ] VOY-222 AC mapped to passing evidence.
    - [ ] Boundary audit passes for `Entities/Ai`, `AiChat`, and FileManager host-only constraint.
    - [ ] Focused tests pass; full Voyager test/build decision is recorded with command and result.

    **QA Scenarios**:

    ```
    Scenario: Issue AC evidence is complete
      Tool: Bash
      Steps: Verify `.sisyphus/evidence/voy-231-ac-matrix.md` lists VOY-237, VOY-238, VOY-219, VOY-222 with command/evidence references.
      Expected: Every issue has happy and failure/edge evidence.
      Evidence: .sisyphus/evidence/task-8-ac-matrix.txt

    Scenario: Boundary audit passes
      Tool: Bash
      Steps: Run import/search checks for upward dependencies and FileManager chat semantics ownership.
      Expected: No forbidden imports or ownership leaks.
      Evidence: .sisyphus/evidence/task-8-boundary-audit.txt
    ```

    **Commit**: YES | Message: `test(aichat): verify contextual chat flow`

## Final Verification Wave (MANDATORY — after ALL implementation tasks)

> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.
> **Do NOT auto-proceed after verification. Wait for user's explicit approval before marking work complete.**
> **Never mark F1-F4 as checked before getting user's okay.** Rejection or user feedback -> fix -> re-run -> present again -> wait for okay.

- [x] F1. Plan Compliance Audit — oracle

    **Agent Invocation**: `task(subagent_type="oracle", load_skills=[], run_in_background=true, prompt="Audit implementation against .sisyphus/plans/voy-231-aichat-orchestration.md. Verify every TODO, wave gate, STOP condition, and issue-level AC has evidence. Return APPROVE/REJECT with blocking gaps only.")`

    **Executable QA Scenarios**:

    ```
    Scenario: Plan evidence completeness audit
      Tool: Bash + Read
      Steps: Verify `.sisyphus/evidence/` contains task evidence for tasks 1-8 and a VOY-237/238/219/222 AC matrix. Read the matrix and confirm every plan AC has a command/result reference.
      Expected: APPROVE only if all task evidence exists and every AC maps to a passing command/result.
      Evidence: .sisyphus/evidence/f1-plan-compliance.md

    Scenario: Wave gate enforcement audit
      Tool: Bash + Grep
      Steps: Search evidence for Wave 0-4 gate outcomes and STOP condition checks: upward imports, FileManager chat ownership, partial persistence, cancel late chunks, in-flight model mutation.
      Expected: APPROVE only if every gate is explicitly passed before dependent wave evidence begins.
      Evidence: .sisyphus/evidence/f1-wave-gates.md
    ```

- [x] F2. Code Quality Review — category `unspecified-high`

    **Agent Invocation**: `task(category="unspecified-high", load_skills=["voyager-dev"], run_in_background=true, prompt="Review implementation quality for VOY-231 AiChat. Focus on TCA ownership, FSD dependencies, duplicate abstractions, concurrency/cancellation, Sendable safety, test quality, and local code smells. Return APPROVE/REJECT with P0/P1 blockers only.")`

    **Executable QA Scenarios**:

    ```
    Scenario: FSD and public boundary code review
      Tool: Grep + Read
      Steps: Inspect changed files and search for forbidden imports or ownership leaks in `apps/macos/Packages/04_Features/AiChat`, `apps/macos/Packages/05_Entities/Ai`, and FileManager touched files.
      Expected: APPROVE only if dependency direction remains App/Pages -> Features -> Entities -> Shared and public surfaces are narrow.
      Evidence: .sisyphus/evidence/f2-code-quality-boundary.md

    Scenario: TCA reducer ownership review
      Tool: Read
      Steps: Inspect `AiChat` State/Action/Reducer and FileManager integration. Confirm external IO is behind Api clients, cancellation IDs live in the feature owner, and UI sends only view actions.
      Expected: APPROVE only if no IO/business orchestration leaks into SwiftUI views or FileManager adapters.
      Evidence: .sisyphus/evidence/f2-tca-ownership.md
    ```

- [x] F3. Real Agent QA — category `unspecified-high`

    **Agent Invocation**: `task(category="unspecified-high", load_skills=["voyager-dev"], run_in_background=true, prompt="Execute real QA for VOY-231 AiChat using package tests, focused FileManager tests, boundary searches, and app smoke where available. Do not rely on visual human inspection. Return APPROVE/REJECT with commands and evidence.")`

    **Executable QA Scenarios**:

    ```
    Scenario: Package and focused test execution
      Tool: Bash or XcodeBuildMCP
      Steps: Run `xcrun swift test --package-path apps/macos/Packages/05_Entities/Ai`, `xcrun swift test --package-path apps/macos/Packages/04_Features/AiChat`, and focused FileManager tests discovered by executor.
      Expected: All commands exit 0. Failures must include root-cause summary and owning wave.
      Evidence: .sisyphus/evidence/f3-test-execution.txt

    Scenario: App-level smoke verification
      Tool: XcodeBuildMCP preferred, Bash fallback
      Steps: Run `xcodebuild test -scheme Voyager-Dev -project apps/macos/Voyager/Voyager.xcodeproj -only-testing:VoyagerTests/Pages/FileManager` or exact focused suite. If XcodeBuildMCP is available, use it and capture result.
      Expected: Focused app tests pass; if environment blocks execution, evidence records blocker and equivalent package-level coverage.
      Evidence: .sisyphus/evidence/f3-app-smoke.txt
    ```

- [x] F4. Scope Fidelity Check — category `deep`

    **Agent Invocation**: `task(category="deep", load_skills=[], run_in_background=true, prompt="Check VOY-231 implementation scope fidelity against Linear VOY-231/237/238/219/222 and VOY-235. Verify in-scope behavior is present and out-of-scope behavior is absent. Return APPROVE/REJECT with blocking scope drift only.")`

    **Executable QA Scenarios**:

    ```
    Scenario: In-scope issue coverage
      Tool: Read + Grep
      Steps: Compare implementation evidence against VOY-237 entry/basic UI, VOY-238 model selection, VOY-219 request execution, VOY-222 session continuity.
      Expected: APPROVE only if each issue has at least one happy-path and one failure/edge evidence item.
      Evidence: .sisyphus/evidence/f4-scope-coverage.md

    Scenario: Out-of-scope drift check
      Tool: Grep
      Steps: Search changed source for MCP/tool execution/file-operation approval/background-agent/long-term-memory/multi-provider-routing concepts outside explicit comments/tests.
      Expected: APPROVE only if no out-of-scope product behavior is introduced.
      Evidence: .sisyphus/evidence/f4-scope-drift.md
    ```

## Commit Strategy

- Prefer one commit per wave/task group after tests pass.
- Do not commit `.sisyphus/` artifacts unless the repository policy explicitly allows local evidence; AGENTS says `.sisyphus/` is local-only and must never be staged/committed.
- Suggested commit sequence:
    1. `feat(ai): add chat contract types`
    2. `feat(aichat): scaffold standalone feature package`
    3. `feat(aichat): add entry and model selection state`
    4. `feat(aichat): handle streaming request lifecycle`
    5. `feat(aichat): maintain session continuity`
    6. `feat(filemanager): mount contextual ai chat`
    7. `test(aichat): verify contextual chat flow`

## Success Criteria

- One reusable `AiChat` feature package owns current-context chat behavior.
- `Entities/Ai` remains a lower-layer contract/provider/auth foundation.
- FileManager only adapts context and hosts the feature.
- Each child Linear issue has passing, agent-executable AC evidence.
- No out-of-scope agent/tool/MCP/long-term memory behavior is introduced.

## ADR

### Decision

Implement VOY-231 as one strict wave-gated Sisyphus plan centered on a new `04_Features/AiChat` package, with `05_Entities/Ai` contracts below it and FileManager as a thin host above it.

### Drivers

- Avoid duplicated chat state machines across VOY-237/238/219/222.
- Preserve FSD dependency direction.
- Make streaming/cancellation/session invariants reducer-testable before integration.

### Alternatives Considered

- **FileManager/Inspector-owned chat**: rejected because it mixes page context and chat semantics and prevents reuse.
- **Entities/Ai-owned chat orchestration**: rejected because entity layer would own feature/session/UI semantics.
- **Separate runs per issue**: rejected because contract churn and duplicated abstractions are likely.

### Why Chosen

The chosen plan keeps ownership aligned: entities define reusable contracts, feature owns use-case behavior, page hosts and adapts context.

### Consequences

- More upfront scaffolding and tests, but fewer cross-issue ownership conflicts.
- Wave gates reduce parallelism but prevent hidden boundary drift.

### Follow-ups

- Optional second entry points: context menu and key command after toolbar path is green.
- Optional richer session strategy after MVP fallback rules are proven.
