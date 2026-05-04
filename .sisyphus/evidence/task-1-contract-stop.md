# VOY-231 Wave 0 STOP Conditions

## Immediate STOP conditions

1. STOP on upward imports.
    - Stop if `AiChat` imports `Pages`, `FileManager`, or app-only types.
    - Stop if `Entities/Ai` imports feature or page types.

2. STOP on FileManager chat ownership.
    - Stop if FileManager mutates request, transcript, session, or model lifecycle state.
    - Stop if host code decides request execution policy instead of only translating context.

3. STOP on partial persistence.
    - Stop if draft deltas are persisted as transcript history.
    - Stop if any stream chunk is treated as final transcript before final response / onFinish.

4. STOP on cancel late chunks.
    - Stop if cancelled or superseded request IDs can still mutate UI, transcript, or session state.
    - Stop if the reducer trusts SDK cancellation as the only guard.

5. STOP on in-flight model mutation.
    - Stop if an active processing request can be re-bound to a newly selected model.
    - Stop if model selection affects the current request instead of `next-request-only`.

6. STOP on missing reducer AC tests.
    - Stop if `request_context_locked`, `next-request-only`, `final transcript exactly-once`, or restore fallback behavior are not covered in reducer tests before integration.

7. STOP on contradictory CBW/code/SDK facts.
    - Stop if the local specs disagree with this plan on context locking, model selection, session restore, or cancel semantics.
    - Stop if a contradiction is found, update the plan before implementation instead of papering over it in code.

## Required fallback rule

- `rebind_required` is allowed as an internal / ephemeral reducer fact only.
- MVP behavior still ends in `new_session fallback` for restore failure, context mismatch, or missing record.

## Verification commands executed

- `python3 - <<'PY' ...` — checked that the file contains `upward imports`, `FileManager chat ownership`, `partial persistence`, `cancel late chunks`, `in-flight model mutation`, `missing reducer AC tests`, `rebind_required`, and `new_session fallback`.

## Verification results

- `TERMS_OK: True`
- `MISSING: []`
- `upward imports: YES`
- `FileManager chat ownership: YES`
- `partial persistence: YES`
- `cancel late chunks: YES`
- `in-flight model mutation: YES`
- `missing reducer AC tests: YES`
- `rebind_required: YES`
- `new_session fallback: YES`
