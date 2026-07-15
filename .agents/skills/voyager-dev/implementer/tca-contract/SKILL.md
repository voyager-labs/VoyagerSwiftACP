---
name: tca-contract
description: Implements Voyager TCA reducer, effect, dependency, state/action, and observation lifecycle contract changes. Use when editing reducers, dependencies, async effects, cancellation, State/Action ownership, or reducer-owned SwiftUI/AppKit observation under apps/macos.
compatibility: opencode
metadata:
    parent_skill: voyager-dev
    role: implementer
    shape: tca-contract
---

# Voyager Dev TCA Contract Implementer

## Instructions

1. Load `references/tca-contract.md` and `references/development-rules.md` before editing; for state/action, effect, navigation, performance, test, or anti-pattern decisions, load the matching focused reference in this directory; for system observation, callbacks, notifications, or long-lived tasks, also load `references/observation-lifecycle-rule.md` and `references/observation-lifecycle-spec.md`.
2. Keep external calls behind dependency clients and route success/failure through typed actions.
3. Keep multi-step async user intents under one cancellation boundary when later steps can commit durable state.
4. Keep transient process state from leaking into durable semantic state.
5. Add layer/boundary references only when files move across FSD boundaries.
6. Keep views as lifecycle/action senders; reducers own external/system observation through dependency clients, explicit start/stop actions, and feature-owned cancellation.
7. Verify start, cancellation, late-event handling, and semantic event routing; load `../spec-test-authoring/references/testing-playbook.md` when lifecycle or reducer tests change.
