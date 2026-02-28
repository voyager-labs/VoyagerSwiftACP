---
name: changelog
description: Compiles recent changes into a user/release-focused changelog. Used when generating release notes.
compatibility: opencode
metadata:
    workflow: release
    output: notes
---

# Changelog Generator

## Purpose

Convert code changes into readable release notes. Focus on what changed for the user, highlighting breaking changes and migrations.

## Workflow

1. **Determine Changelog System**
    - Priority: `CHANGELOG.md` > `.changeset/` > `releases/` > `docs/release-notes*`.
    - If none exists: Draft a "Release notes" section to be used in a PR description.

2. **Categorize Changes**
    - `Added`: New features
    - `Changed`: Behavior/UX modifications
    - `Fixed`: Bug fixes
    - `Removed/Deprecated`: Dropped support or deprecations
    - `Security`: Vulnerability patches

3. **Format for the Audience**
    - Clarify if the change affects Developers, Users, or Operators.
    - Include configuration changes or migration steps if necessary.
    - Omit deep implementation details.

4. **Verification & Risks**
    - Add a 1-liner on tests/QA performed.
    - Note any rollback points or critical risks.

## Output Format (Recommended)

```markdown
## Release notes

### Added

- ...

### Changed

- ...

### Fixed

- ...

### Notes

- Validation: ...
- Risk: ...
```
