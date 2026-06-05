---
name: tca-contract
description: Implements Voyager TCA reducer, effect, dependency, and state/action contract changes. Use when editing reducers, dependencies, async effects, cancellation, or State/Action ownership under apps/macos.
compatibility: opencode
metadata:
    parent_skill: voyager-dev
    role: implementer
    shape: tca-contract
---

# Voyager Dev TCA Contract Implementer

## Instructions

1. Load `references/tca-contract.md` and `references/development-rules.md` before editing.
2. Keep external calls behind dependency clients and route success/failure through typed actions.
3. Keep multi-step async user intents under one cancellation boundary when later steps can commit durable state.
4. Keep transient process state from leaking into durable semantic state.
5. Add layer/boundary references only when files move across FSD boundaries.
