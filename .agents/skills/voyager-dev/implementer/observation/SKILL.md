---
name: observation
description: Implements Voyager reducer-owned observation lifecycle changes. Use when moving SwiftUI/AppKit system observation, callbacks, notifications, or long-lived tasks from views into TCA reducers.
compatibility: opencode
metadata:
    parent_skill: voyager-dev
    role: implementer
    shape: observation-refactor
---

# Voyager Dev Observation Implementer

## Instructions

1. Load `.agents/rules/30-macos/02-tca-observation-lifecycle.md` for the canonical lifecycle invariant, then load `references/observation-lifecycle-spec.md` and `../tca-contract/references/tca-contract.md` for procedure.
2. Keep views as lifecycle/action senders; reducers own external/system observation through dependency clients, explicit start/stop actions, and feature-owned cancellation.
3. Verify start, cancellation, and semantic event routing; add `../references/testing-playbook.md` when lifecycle or reducer tests change.
