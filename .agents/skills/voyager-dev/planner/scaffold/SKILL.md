---
name: scaffold
description: Plans Voyager macOS FSD/TCA scaffolding and package wiring. Use when adding new apps/macos modules, slices, packages, or feature shells before implementation.
compatibility: opencode
metadata:
    parent_skill: voyager-dev
    role: planner
    shape: scaffold
---

# Voyager Dev Scaffold Planner

## Instructions

1. Confirm the target layer, slice boundary, package ownership, and omitted segments.
2. Load scaffold references: `references/scaffold-spec.md` and `references/package-extraction-posture.md`.
3. Add `references/app-thin-integration-spec.md` only when package-to-app wiring changes.
4. Add boundary references from `../../reviewer/review/references/` when layer choice, segment placement, or public API changes.
5. Emit the file list to add/modify, dependency direction, public boundary, and verification commands.
6. Do not implement code from this planner role.
