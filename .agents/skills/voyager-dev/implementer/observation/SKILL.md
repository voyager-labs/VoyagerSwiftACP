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

1. Load `references/observation-lifecycle-spec.md` and `../tca-contract/references/tca-contract.md`.
2. Keep views as lifecycle/action senders; reducers own external/system observation.
3. Use dependency clients and explicit start/stop lifecycle actions.
4. Assign a feature-owned cancellation boundary and verify start/cancel behavior.
5. Add `../../verifier/testing/references/testing-playbook.md` when lifecycle or reducer tests change.
