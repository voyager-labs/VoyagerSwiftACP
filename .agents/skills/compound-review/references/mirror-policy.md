# Mirror Policy: `.agents/` vs `.claude/skills/`

## Authority

**`.agents/skills/compound-review/` is the single source of truth.**

`.claude/skills/compound-review/` is a read-only mirror. It exists for toolchains that discover skills via `.claude/skills/` paths. All edits, reviews, and versioning happen in `.agents/`.

## v1 Rules

1. **Edit authority**: All changes go to `.agents/skills/compound-review/` first.
2. **Mirror is downstream**: `.claude/skills/compound-review/` should reflect `.agents/` content, but mirroring is not automated in v1. Drift between the trees is possible and expected until a sync mechanism is added.
3. **Conflict resolution**: When `.agents/` and `.claude/` disagree, `.agents/` wins. Always.
4. **No split ownership**: Never edit `.claude/skills/compound-review/` independently. If you need to change the skill, change `.agents/` and then manually copy to `.claude/` if needed.
5. **Discoverability**: `compound-review` serves as the synthesis hub for the governance skill lifecycle. Skills are discovered via the standard `.agents/skills/` directory structure — there is no central registry.

## Why This Matters

Truth drift across mirrors is a known risk. A single authoritative tree with a documented mirror policy is safer than bidirectional sync without a clear owner. v1 prioritizes correctness over automation.

## Future

If a future task adds automated mirroring (e.g., git hook or CI check), this doc should be updated to describe the sync mechanism. Until then, manual copy is acceptable.
