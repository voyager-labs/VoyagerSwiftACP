# Contract TOML Spec

This document defines the recommended shape for `PRODUCT/05_FEATURE_SPECS/<category>/contracts/*.toml`.

Use it when authoring or updating category-level contract files.

## Goal

A contract TOML file exists to make shared object/state vocabulary explicit and machine-readable.

It should answer:

- what is the primary object?
- what secondary objects are truly needed?
- what are the allowed user-visible states?
- what state terms are forbidden?
- which interactions read or write which states?
- which transitions are allowed?

Do not use contract TOML files for long prose explanations or flow narration.

## File Placement

Path pattern:

- `PRODUCT/05_FEATURE_SPECS/<category>/contracts/<name>.toml`

Examples:

- `PRODUCT/05_FEATURE_SPECS/cbw/contracts/request_lifecycle.toml`
- `PRODUCT/05_FEATURE_SPECS/cbw/contracts/conversation_session_contract.toml`

## Top-level Sections

Recommended sections:

- `[contract]`
- `[vocabulary]`
- `[policy]`
- `[user_visible_states]` or `[user_visible_status]`
- `[state.<state_name>]` or `[status.<status_name>]`
- `[ownership."<interaction_id>"]`
- `[transitions.<transition_name>]`

Keep the structure shallow. Prefer a few stable sections over many nested aliases.

## Required Concepts

### `[contract]`

Required fields:

- `id`
- `category`
- `primary_object`

Optional fields:

- `secondary_objects`
- `display_region`
- `scope_region`

Example:

```toml
[contract]
id = "cbw.request_lifecycle"
category = "CBW"
primary_object = "request"
secondary_objects = ["response", "turn"]
```

### `[vocabulary]`

Use this section to define the exact meaning of object names or shared terms.

Example:

```toml
[vocabulary]
request = "사용자가 chat prompt를 제출했을 때 생성되는 사용자 단위 요청 객체"
response = "하나의 request에 연결된 assistant 출력"
turn = "하나의 request와 그 request에 연결된 response를 묶는 대화 단위"
```

Rules:

- use exact product-facing names
- avoid invented abstractions unless the user explicitly wants them
- if `request` and `response` are enough, do not add more objects

### `[policy]`

Use this section for global boolean or enumerated rules that multiple specs depend on.

Example:

```toml
[policy]
single_processing_response_per_request = true
cancel_allowed_from = ["processing"]
```

Rules:

- use this section for category-wide invariants
- avoid stuffing interaction-local behavior here

### `[user_visible_states]` / `[user_visible_status]`

Use one of these sections to declare the canonical user-visible state vocabulary.

Example:

```toml
[user_visible_states]
allowed = ["processing", "completed", "failed", "cancelled"]
forbidden = ["queued", "cancelling"]
```

Rules:

- `allowed` is the only user-visible vocabulary that specs should use
- `forbidden` captures terms that should not appear in user-facing spec prose

### `[state.<name>]` / `[status.<name>]`

Use one table per declared state or status.

Recommended fields:

- `description`
- `entered_by`
- `exits_to`
- `terminal`
- `user_visible`
- `allows_submit`
- `fallback_status`
- `requires_followup`
- `terms`

Example:

```toml
[state.processing]
description = "요청이 현재 응답 생성 중인 상태"
entered_by = ["CBW-001-submit_chat_request", "CBW-001-regenerate_chat_response"]
exits_to = ["completed", "failed", "cancelled"]
terminal = false
user_visible = true
terms = ["processing"]
```

Rules:

- `terms` should contain the exact prose terms the checker can look for
- use one state name, not a list of near-synonyms
- keep `entered_by` and `exits_to` deterministic

### `[ownership."<interaction_id>"]`

Use keyed subtables, not repeated array-of-table records.

Recommended fields:

- `reads`
- `writes`
- `target_object`
- `creates_objects`
- `preserves_objects`
- `display_region`
- `control_region`

Example:

```toml
[ownership."CBW-001-submit_chat_request"]
reads = []
writes = ["processing"]
target_object = "request"
creates_objects = ["request", "response"]
control_region = "file_manager_window.inspector_pane.inspector_mode_chat.chat_field"
```

Rules:

- the key must be the exact `interaction_id`
- use this section to map interaction responsibility, not to repeat full prose behavior

### `[transitions.<name>]`

Use one keyed subtable per allowed transition.

Required fields:

- `from`
- `to`

Optional fields:

- `trigger`

Example:

```toml
[transitions.processing_to_completed]
from = "processing"
to = "completed"
trigger = "CBW-003-stream_contextual_chat_response"
```

Rules:

- transition names should be readable and stable
- `from` and `to` must use declared state names from `allowed`

## Naming Rules

- use lowercase snake_case for TOML table keys where a free key name is needed
- use exact `interaction_id` for ownership keys
- use exact state names in `allowed`, `forbidden`, `from`, `to`, `reads`, and `writes`

## What Not To Put Here

Do not put these in contract TOML:

- long narrative explanation
- happy-path sequence prose
- UI copy alternatives
- open questions
- speculative implementation details

Those belong in:

- interaction specs
- flow docs
- review notes

## Flow Relationship

Contract TOML defines vocabulary and transitions.

Flow docs explain sequence and branching.

Use:

- `contracts/*.toml` for machine-readable consistency
- `flows/*.md` for human-readable end-to-end flow
