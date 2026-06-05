# Review Playbook

Procedural methods for executing each review area. This file is loaded on
demand when the skill's Phase 4 (Repository-Aware Review Execution) needs
concrete check commands. It does not duplicate policy — every substantive rule
lives in `.greptile/rules.md`.

---

## Diff Collection Commands

Use these to gather the raw material for triage and review.

| Command                                                       | When to use                                                                                                                                                                                 | What it gives you                                                                                                                                  |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `git diff --stat origin/develop...HEAD`                       | Every review — first pass                                                                                                                                                                   | File list with insertions/deletions per file                                                                                                       |
| `git diff --name-only origin/develop...HEAD`                  | Triage — file count and layer classification                                                                                                                                                | Clean file path list (no stats)                                                                                                                    |
| `git diff --stat origin/develop...HEAD \| wc -l`              | Large-PR threshold check                                                                                                                                                                    | Approximate changed-file count (subtract 1 for summary line)                                                                                       |
| `git diff --shortstat origin/develop...HEAD`                  | Triage — total changed lines                                                                                                                                                                | `N files changed, M insertions(+), D deletions(-)`                                                                                                 |
| `git log --oneline origin/develop..HEAD`                      | Intent — commit story                                                                                                                                                                       | Ordered commit list with subjects                                                                                                                  |
| `git show --name-status --pretty=format:'COMMIT %h %s' <sha>` | Per-commit impact                                                                                                                                                                           | Files changed per commit with status (A/M/D/R)                                                                                                     |
| GitHub PR                                                     | `gh pr view <N> --json additions,deletions,changedFiles,baseRefName,headRefName,headRefOid` (metadata)<br>`gh pr diff <N> --name-only` (file list)<br>`gh pr diff <N> --patch` (full patch) | PR metadata + diff via GitHub CLI. No local checkout needed. **Note:** `gh pr diff --stat` is not currently supported — use `--name-only` instead. |

For local diffs (no PR yet), replace `origin/develop...HEAD` with the
appropriate merge base:

```bash
git diff --stat $(git merge-base develop HEAD)...HEAD
```

---

## Large-PR Thresholds

A diff is classified **large** when **any** of these is true:

- **>200 files** changed
- **>1500 changed lines** (insertions + deletions)
- **>3 top-level modules/layers** affected (e.g., `01_App`, `02_Pages`, `04_Features` all in one PR)

When the diff is large:

1. Group changed paths by FSD layer and module.
2. State explicit coverage in the `Coverage` output section.
3. Prioritize reducer, model, API, and storage changes over config/formatting.
4. Use parallel exploration or direct-tool fallback (see §Large-PR Context Gathering below).

---

## Coverage Statement Format

For large PRs (and optional for normal PRs), include a `Coverage` section:

```markdown
## Coverage

| Area                           | Status   | Why skipped                     | Confidence |
| ------------------------------ | -------- | ------------------------------- | ---------- |
| Reducer effects & cancellation | Reviewed | —                               | high       |
| FSD dependency direction       | Reviewed | —                               | high       |
| UI view rendering              | Skipped  | Cosmetic-only changes, no logic | medium     |
| Package.swift manifests        | Skipped  | No new targets or dependencies  | high       |
| Test coverage                  | Reviewed | —                               | medium     |
```

Fields:

- **Area**: The review domain or file group.
- **Status**: `Reviewed` or `Skipped`.
- **Why skipped**: Concrete reason. Never leave blank for a skipped area.
- **Confidence**: `high`, `medium`, or `low`. Low confidence requires an explicit caveat in the Risk section.

**Confidence adjustment:** If CodeGraph was unavailable for a review area that
would benefit from symbol-level analysis (e.g., transitive impact, caller
tracing, cross-language contract verification), lower that area's confidence by
one level and note "CodeGraph unavailable" in the Why skipped column or a
footnote.

---

### Verification Evidence Policy

pr-review는 verification 스킬이 아니다. Local 검증은 선택적.

**PR-provided evidence가 충분한 경우:**

- 변경이 단일 패키지/단일 feature에 한정
- 검증 명령이 변경 파일과 직접 연결
- 리뷰 목적이 구조적 P0/P1 탐지이며 CI 대체가 아님

**Local 검증을 직접 실행해야 하는 경우:**

- PR 설명에 검증 증거가 없음
- reducer lifecycle, persistence, storage, helper/XPC contract처럼 runtime regression 위험 높음
- diff 분석 중 type-level uncertainty 발생
- PR head/local checkout을 기준으로 강한 review decision 필요

---

## Review Methods per Area

> **CodeGraph prerequisite:** If `.codegraph/` index exists (check with `mise run codegraph-status`), prefer CodeGraph tools below. Fall back to grep if index unavailable.

Each subsection gives procedural commands and patterns. Policy details
(e.g., "what to flag") are in `.greptile/rules.md` under the referenced section
heading.

### FSD Dependency Direction

**Policy reference:** `.greptile/rules.md` §Voyager architecture model

1. Extract layer paths from the diff:
    ```bash
    git diff --name-only origin/develop...HEAD | grep -oE '(01_App|02_Pages|03_Widgets|04_Features|05_Entities|06_Shared)' | sort -u
    ```
2. For each changed file in a higher layer, check imports:
    ```bash
    # Preferred: CodeGraph
    codegraph_explore  # top-level module overview
    codegraph_context("<ModuleName>")  # module symbols/dependencies
    # Fallback: grep
    grep -rn 'import.*\(Pages\|Widgets\|Features\|Entities\|Shared\)' <file>
    ```
3. Verify top-to-bottom direction. Flag reverse dependencies.
4. Check `Package.swift` files for cross-layer target dependencies.

### TCA Segment Ownership

**Policy reference:** `.greptile/rules.md` §TCA and segment ownership

1. Identify segment folders in changed paths: `Ui/`, `Reducer/`, `Model/`,
   `Api/`, `Lib/`, `Config/`.
2. For files in `Ui/`, check for IO work:
    ```bash
    grep -nE '(URLSession|FileManager|NSKeyedArchiver|@Observable|onReceive|NotificationCenter)' <view-file>
    ```
3. For files in `Reducer/`, check for direct service construction:
    ```bash
    grep -nE '(URLSession\.\w+|FileManager\.default|NSXPCConnection)' <reducer-file>
    ```
4. Verify state/action types are in `Model/`, not scattered across segments.
5. Check action dispatch ownership:
    ```bash
    # Preferred: CodeGraph (action dispatch site 추적)
    codegraph_callers(symbol: "<Reducer>.Action")
    codegraph_callees(symbol: "<View>.body")
    ```

### Reuse and Duplicate Detection

**Policy reference:** `.greptile/rules.md` §Reuse and duplicate detection,
§Repository-aware review priority

1. For each new type, function, or helper in the diff, search for existing
   equivalents:
    ```bash
    # Preferred: CodeGraph (symbol-level, 간접 참조 추적)
    codegraph_search(query: "<TypeName>")
    codegraph_callers(symbol: "<ExistingSymbol>")
    # Fallback: grep
    grep -rn '<TypeName>' --include='*.swift' apps/macos/
    ```
2. Compare naming: two types representing the same domain concept with
   different names is the most common duplication pattern.
3. Check whether a new utility duplicates a mapping, label, icon, provider,
   status, or formatting helper already in `06_Shared` or the owning entity.
4. Cite the existing path/type in findings. Do not flag speculatively.

### Async Lifecycle and Cancellation

**Policy reference:** `.greptile/rules.md` §Async lifecycle and cancellation

1. Find async/effect code in changed reducers:
    ```bash
    grep -nE '\.run|\.send|Effect|async |await |\.cancel|CancellationId' <reducer-file>
    ```
2. For each async effect, check:
    - Is there a cancellation ID? (`struct CancelId: Hashable {}` or equivalent)
    - Does the close/reset/teardown action cancel in-flight work?
    - Can a late completion event reopen or mutate a closed feature?
    - Is the resolved context captured once and preserved across the chain?
3. Check the owning reducer's teardown/deinit path for cleanup:
    ```bash
    grep -nE 'teardown|onDisappear|cancel|reset|cleanup' <reducer-file>
    ```

### Swift Concurrency Review

**정책 참조:** `.greptile/rules.md` §Async lifecycle and cancellation

**체크 항목:**

1. `@MainActor` vs `actor` vs `nonisolated` 사용이 의도적이고 일관적인지
2. `Task.detached` 사용에 정당성이 있는지 (structured concurrency 선호)
3. Strict concurrency 설정 (`SWIFT_STRICT_CONCURRENCY`, `SWIFT_DEFAULT_ACTOR_ISOLATION`)이 프로젝트 정책과 일치
4. Effect cancellation ID가 모든 async effect에 존재
5. `Sendable` conformance가 실제로 thread-safe한지 (단순 annotation이 아닌)

```bash
grep -nE 'Task\.detached|@MainActor|nonisolated|actor ' <changed-file>
```

### File-backed Storage and Credentials

**Policy reference:** `.greptile/rules.md` §File-backed storage and credentials

1. Identify storage-relevant changes:
    ```bash
    git diff --name-only origin/develop...HEAD | grep -iE '(credential|oauth|provider|settings|storage|keychain|persist|filebacked)'
    ```
2. For each matching file, check:
    - Atomic writes: does the code use write-to-temp + rename?

    ```bash
    grep -nE 'write\(to:|FileManager.*createFile|writeToFile' <storage-file>
    ```

    - File locks for concurrent access:

    ```bash
    grep -nE 'flock|lockfile|NSFileCoordinator|O_EXLOCK' <storage-file>
    ```

    - Restrictive permissions for sensitive data:

    ```bash
    grep -nE '0o600|0o700|attributes|permissions' <storage-file>
    ```

    - No secrets in UserDefaults or plist:

    ```bash
    grep -nE 'UserDefaults|\.plist' <storage-file>
    ```

3. Flag storage path mismatches as correctness/data-loss risks (not style).

### Environment, Secrets, and Build Settings

**Policy reference:** `.greptile/rules.md` §Environment, secrets, and build settings

1. Identify env/build-setting changes:
    ```bash
    git diff --name-only origin/develop...HEAD | grep -E '(\.env|Info\.plist|\.entitlements|\.xcscheme|copy-bundled-env|EnvironmentLoader|SentryBootstrap|HelperAppClient)'
    ```
2. For matching files, search for secret-bearing or runtime-selection patterns:
    ```bash
    grep -nE '(APP_ENV|PUBLIC_|SECRET|TOKEN|KEY|DSN|\.env\.dev|\.env\.prod|ProcessInfo\.processInfo\.environment)' <changed-file>
    ```
3. Check whether release paths copy only secret-free templates, helper/XPC
   launches receive an explicit env allowlist, and `Info.plist`/scheme changes
   preserve debug/release behavior.
4. Treat secret exposure, bundled local env, or app/helper env mismatch as
   runtime/security risk. Do not flag cosmetic plist formatting.

### Helper and XPC Contracts

**Policy reference:** `.greptile/rules.md` §Helper and XPC contracts

1. Identify helper/XPC surfaces:
    ```bash
    git diff --name-only origin/develop...HEAD | grep -E '(XPC|Helper|SearchXPCTransport|FilterSearchXPCProtocol|HelperStateBroadcaster|ExternalFileChange)'
    ```
2. For protocol or transport changes, verify both sides of the contract:
    - shared protocol/model changes
    - app-side transport/client changes
    - helper/XPC service implementation changes
    - tests/fixtures that exercise timeout, termination, unavailable-helper,
      replay, or restore paths
3. Search for bypasses around the contract:
    ```bash
    grep -nE '(NotificationCenter|NSXPCConnection|Process|FileManager\.default|UserDefaults\.standard)' <changed-file>
    ```
4. Flag one-sided protocol updates, app-only assumptions, and missing failure
   paths only when they create concrete runtime mismatch.

### Package and Public Boundaries

**Policy reference:** `.greptile/rules.md` §Package and public boundaries

1. Identify Swift package boundary changes:
    ```bash
    git diff --name-only origin/develop...HEAD | grep -E '(apps/macos/Packages/.*/Package\.swift|apps/macos/Packages/.*/Sources/|apps/macos/Packages/.*/Tests/)'
    ```
2. Search package code for app-target coupling or upper-layer imports:
    ```bash
    # Preferred: CodeGraph (transitive impact)
    codegraph_impact(symbol: "<PackageOrSymbol>", depth: 2)
    # Fallback: grep
    grep -nE '(@testable import Voyager|import Voyager|import .*Pages|import .*Widgets|import .*Features)' <package-file>
    ```
3. For promoted public APIs, check that the required initializer, stored
   properties, enum cases, dependency clients, and test fixtures are public
   enough for real consumers.
4. Treat incomplete public surfaces, compatibility wrappers without a stable
   boundary, and package-to-app dependencies as ownership risks.

### AppKit Coordinator Correctness

**Policy reference:** `.greptile/rules.md` §AppKit coordinator review

1. Identify coordinator code in the diff:
    ```bash
    git diff --name-only origin/develop...HEAD | grep -iE '(coordinator|appkit|nsview|nswindow|NSSplitView)'
    ```
2. For each coordinator file, check:
    - Does the reducer assume a view is physically mounted before the
      coordinator confirms it?
    - Does a coordinator mutate reducer state before the AppKit operation
      actually succeeds?
    - Does the close/unmount path cancel pending open/setup effects?
    - Can retry logic get stuck in logical-open / physically-missing state?
3. Search for mount/state assumptions:
    ```bash
    grep -nE 'isMounted|isAttached|isReady|window\.' <coordinator-file>
    ```

### Cross-feature Command Routing

**Policy reference:** `.greptile/rules.md` §Cross-feature command routing

1. Identify cross-feature actions in the diff:
    ```bash
    git diff --name-only origin/develop...HEAD | grep -E '(Reducer|Action)'
    ```
2. Check for:
    - Direct mutation of another feature's state (grep for state accesses
      across module boundaries).
    - View-to-view communication for domain behavior.
    - Global notification routing when a reducer action path exists:
    ```bash
    # Preferred: CodeGraph (실제 호출 경로)
    codegraph_trace("<ViewAction>", "<TargetHandler>")
    # Fallback: grep
    grep -nE 'NotificationCenter|UserDefaults\.standard|NSApplication\.shared' <changed-file>
    ```

### Backend API Contracts

**Policy reference:** `.greptile/rules.md` §Backend API contracts

1. Identify gateway/API changes in the diff:
    ```bash
    git diff --name-only origin/develop...HEAD | grep -E '(Gateway|ApiClient|Route|Endpoint)'
    ```
2. For Swift–Python cross-language contract changes:
    ```bash
    # Preferred: CodeGraph (Swift→Python cross-language)
    codegraph_trace("<SwiftGateway>", "<PythonRoute>")
    ```
3. Verify request/response schema alignment between Swift client and Python route.
4. Flag missing error handling, mismatched field names, or divergent enum cases.

### Test Review

**Policy reference:** `.greptile/rules.md` §Test review

1. Identify test files in the diff:
    ```bash
    git diff --name-only origin/develop...HEAD | grep -iE 'Test[s/]'
    ```
2. For TCA test files, check:
    - Are effects cancellable where needed?

    ```bash
    grep -nE 'cancel|cancellation|teardown' <test-file>
    ```

    - Are delegate actions and parent routing covered?
    - Are failure, cancel, restore, teardown, and late-event paths covered?
    - Do tests model external coordinator/system state explicitly?

3. Do not ask for tests generically. Name the missing behavior.

### Xcode Test Plan Visibility

**Policy reference:** `.greptile/rules.md` §Test review

Use this procedural check when a PR changes Swift packages, Xcode project files,
test plans, or claims package-level verification.

1. Identify package and Xcode test surfaces:
    ```bash
    git diff --name-only origin/develop...HEAD | grep -E '(Package.swift|Tests/|\.xctestplan|\.xcodeproj)'
    ```
2. Check whether the stated verification command actually runs the intended
   package test target. Do not assume an auto-created Xcode test plan includes
   SwiftPM package tests.
3. If package behavior changed but no package test target is visible in the
   verification evidence, record the gap in `Tests/QA` or a finding only when it
   leaves a concrete P1 regression risk.

### Affected Checks and LSP Context

Use this procedural check when the diff crosses app/helper/XPC/host/package
boundaries or touches build settings.

1. Group changed files by target: app, helper, XPC, host, package, tests.
2. Select review context and verification evidence for the affected targets;
   do not apply app-only assumptions to helper/XPC/package changes.
3. Treat `buildServer.json` and IDE/LSP context changes as local/generated
   context unless the PR explicitly changes shared tooling policy.

### Local Artifact Hygiene

**Policy reference:** `.greptile/rules.md` §Local-only artifacts

1. Check the diff for local-only paths:
    ```bash
    git diff --name-only origin/develop...HEAD | grep -E '\.(omx|sisyphus)/'
    ```
2. If any match is found, this is a P0/P1 repository hygiene finding
   regardless of other content.
3. Also check staged files:
    ```bash
    git diff --cached --name-only | grep -E '\.(omx|sisyphus)/'
    ```

---

## Large-PR Context Gathering

When the diff exceeds the large-PR thresholds, the reviewer cannot read every
file in sequence. Use one of two strategies depending on whether background
agents (subagents) are available.

### Strategy A: Parallel Explore Agents (preferred when available)

Dispatch 2–3 background explore agents. Each agent receives a focused scope so
their outputs do not overlap. Collect results, then proceed to review execution.

**Anti-duplication rule:** Once you dispatch an explore agent for a topic, do
NOT manually grep or search for the same information. Wait for the agent's
results, then proceed. Repeating delegated searches wastes context and can
produce contradictory findings.

#### Prompt template: Architecture Boundary

```
Review the FSD dependency direction in these changed files for the Voyager macOS
app. The allowed layer direction is top-to-bottom:
01_App -> 02_Pages -> 03_Widgets -> 04_Features -> 05_Entities -> 06_Shared.

Changed files to check:
<file list from triage>

For each file, verify:
1. No reverse imports (lower layer importing higher layer).
2. No same-layer slices directly depending on each other.
3. Package.swift targets follow the same direction.

Report exact file paths and import lines that violate direction.
Policy reference: .greptile/rules.md §Voyager architecture model.
```

#### Prompt template: Async Lifecycle and Cancellation

```
Review async effect lifecycle correctness in these changed reducer files:
<reducer file list from triage>

For each reducer, check:
1. Does every .run / .send / Effect have a cancellation ID?
2. Does the close/reset/teardown path cancel in-flight work?
3. Can a late completion event reopen or mutate a closed feature?
4. Is the resolved context captured once and preserved across the async chain?
5. Are failure and rollback paths handled by the canonical owner?

Search for patterns: .run, .send, Effect, async, await, .cancel, CancellationId.
Report concrete file paths and line numbers.

Policy reference: .greptile/rules.md §Async lifecycle and cancellation.
```

#### Prompt template: Credential and Storage Paths

```
Review file-backed storage and credential handling in these changed files:
<storage file list from triage>

For each file, check:
1. Atomic writes: write-to-temp + rename, not direct overwrite.
2. File locks where concurrent access is possible.
3. Restrictive file permissions for sensitive files.
4. No secrets in UserDefaults, plist, or plain text.
5. Storage path consistency — verify paths match design conventions.

Search for patterns: write(to:, FileManager, UserDefaults, .plist, 0o600.
Report concrete file paths and line numbers.

Policy reference: .greptile/rules.md §File-backed storage and credentials.
Also see: .agents/rules/30-macos/06-file-backed-storage-invariants.md
```

#### Dispatch sequence

1. Triage the diff (Phase 2 of the skill workflow) to identify which hotspots
   are present.
2. Dispatch only the agents whose hotspot appears in the diff. If no async
   effects changed, skip the async-lifecycle agent.
3. Wait for all dispatched agents to complete.
4. Merge their findings into the review execution phase. Do not re-run their
   searches manually.

### Strategy B: Direct-Tool Fallback (when no background agents)

When subagents are unavailable, review files directly in priority order:

| Priority | File category        | What to check                                | Tools          |
| -------- | -------------------- | -------------------------------------------- | -------------- |
| 1        | Reducers             | Ownership, effects, cancellation             | `read`, `grep` |
| 2        | Models               | State/action structure, type placement       | `read`         |
| 3        | API clients          | Dependency client construction, live values  | `read`, `grep` |
| 4        | Storage/persistence  | Atomic writes, permissions, path consistency | `read`, `grep` |
| 5        | Coordinators         | Physical vs logical state, mount assumptions | `read`, `grep` |
| 6        | Views                | IO in views, cross-feature routing           | `grep`         |
| 7        | Tests                | Architecture-relevant coverage               | `read`         |
| 8        | Config/Package.swift | Dependency direction, new targets            | `read`         |

Steps:

1. Group changed files by the categories above.
2. Read files in priority order, highest first.
3. For each file, run the applicable check commands from the §Review Methods
   per Area section.
4. Record coverage as you go — mark each group `Reviewed` or `Skipped` with a
   reason.
5. If the diff is too large to complete all groups, state which groups were
   skipped and set confidence to `medium` or `low`.

**Time budget for large PRs:** If after reviewing priority 1–4 groups the
context budget is running low, skip remaining groups, mark them `Skipped` with
reason "context budget", and set overall confidence to `medium`.

### Normal PRs (not large)

For diffs below the large-PR thresholds, skip agent dispatch entirely. Read
changed files directly using the commands in §Review Methods per Area. No
coverage statement is required unless the reviewer judges it helpful.
