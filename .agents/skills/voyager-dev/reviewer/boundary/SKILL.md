---
name: boundary
description: Reviews Voyager FSD layer, segment, slice, and public boundary compliance. Use when files move across Ui/Model/Reducer/Api/Lib or when package public APIs change.
compatibility: opencode
metadata:
    parent_skill: voyager-dev
    role: reviewer
    shape: boundary
---

# Voyager Dev Boundary Reviewer

## Instructions

1. Load `references/layer-and-segment-rules.md` and `references/public-boundary-spec.md`.
2. Verify FSD dependency direction, public API necessity, and segment ownership.
3. Check for reverse imports, widget-owned `Api/`, and page logic leaking downward.
4. Check for internal symbols promoted to public without cross-package consumer evidence. Distinguish compiler-required public (associated value types in public enums, protocol witness methods on public classes) from unjustified expansion during Swift 6 migration.
5. Report PASS/FAIL with exact paths and the violated boundary if any.
6. Do not suggest style nits unrelated to boundary correctness.
