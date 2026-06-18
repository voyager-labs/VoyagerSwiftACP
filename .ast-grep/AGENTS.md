# ast-grep Lint Rules

Structural lint rules for the Voyager codebase, organized by FSD segment.

## Directory Structure

```
.ast-grep/
  rules/
    <segment>/    ← Rules scoped to a specific FSD segment (model, reducer, ui, …)
    common/       ← Rules that apply across all segments
  utils/          ← (reserved) shared utilities
  rule-tests/     ← (reserved) rule test snapshots
sgconfig.yml      ← ruleDirs: .ast-grep/rules (recursive)
```

Rules are grouped by FSD segment. Each segment directory contains rules that
apply **only** to that layer. Cross-cutting rules that apply everywhere go in
`common/`.

## Segment Scope

| Segment    | Scan target                           | Description                                   |
| ---------- | ------------------------------------- | --------------------------------------------- |
| `common/`  | `apps/macos/**/*.swift` (excl. Tests) | Rules applicable to all layers                |
| `model/`   | `apps/macos/**/*.swift` (excl. Tests) | Model layer conventions (State, Action, etc.) |
| `reducer/` | `apps/macos/**/*.swift` (excl. Tests) | Reducer layer conventions (@Reducer, etc.)    |
| `ui/`      | `**/Ui/*.swift` (excl. Tests)         | Ui layer constraints (no direct observation)  |

New FSD segments (e.g. `api/`, `lib/`) can be added by creating a directory
under `rules/` and updating the lefthook scan block accordingly.

## Execution

- **Automatic**: lefthook pre-push hook runs rules per segment
    - `common/`, `model/`, `reducer/` → all non-test sources
    - `ui/` → `*/Ui/*.swift` only (avoids false positives in Api/Infrastructure)
- **Manual**: `mise exec -- ast-grep scan --rule .ast-grep/rules/<segment>/<rule>.yaml`
- All rules use `severity: warning` + `|| true` — push is never blocked

## Adding a New Rule

1. Determine which FSD segment the rule belongs to.
    - If it applies to a single layer → use that segment's directory.
    - If it applies everywhere → use `common/`.
2. Create a YAML file in the chosen directory.
3. Include: `id`, `language: swift`, `severity: warning`, `message` (Korean), `note` (English).
4. Rules in `common/`, `model/`, and `reducer/` are picked up automatically by the
   non-test scan loop. Rules in `ui/` are picked up by the Ui-only scan loop.
   No lefthook changes needed for existing segments.

## Current Rules

### model/

- `action-missing-casepathable` — Action enum missing @CasePathable annotation
- `observable-state-on-typealias` — @ObservableState applied to non-concrete type

### reducer/

- `reducer-missing-typealias` — @Reducer struct missing State/Action typealias
- `nested-state-in-reducer` — State/Action defined inline inside @Reducer

### ui/

- `ui-direct-observation` — Direct NotificationCenter usage in Ui files
- `ui-direct-userdefaults` — Direct UserDefaults.standard usage in Ui files
