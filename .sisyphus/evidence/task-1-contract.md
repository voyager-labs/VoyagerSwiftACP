# VOY-231 Wave 0 Contract Traceability

## Issue-to-wave mapping

| Issue   | Wave    | Why                                                                                                                                                           |
| ------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| VOY-237 | Wave 2b | AiChat entry surface, context summary, model selection state, and next-request-only model semantics belong in the standalone feature before host integration. |
| VOY-238 | Wave 2b | Active model display, fallback to first catalog row, and model display semantics are part of the AiChat state machine, not FileManager.                       |
| VOY-219 | Wave 2c | Execution, streaming, cancellation, late-chunk ignoring, and finalization are reducer-owned lifecycle behavior.                                               |
| VOY-222 | Wave 2d | Session continuity, restore, rebind / fallback, and transcript normalization are feature-owned restore policy.                                                |

## CBW contract mapping

| CBW contract / flow             | Hard requirement for VOY-231                                                                  |
| ------------------------------- | --------------------------------------------------------------------------------------------- |
| `request_context_locked`        | Submit / regenerate must freeze the request context snapshot before preparation.              |
| `next-request-only`             | Model changes apply to the next request only; in-flight processing must not be mutated.       |
| `final transcript exactly-once` | The final assistant turn is persisted once from the final response / onFinish path only.      |
| `new_session fallback`          | Restore failure, invalid record, or context mismatch must fall back to `new_session` for MVP. |

## Entities/Ai allowlist

- Provider/auth/model catalog DTOs and contracts only.
- Request / response / event DTOs.
- Session status / restore status DTOs.
- Request context snapshot DTOs needed by AiChat.
- Dependency client contracts for execution and session persistence.

## Entities/Ai denylist

- AiChat state, actions, reducer, or view types.
- FileManager / Pages / Voyager app imports.
- UI-owned observation or orchestration.
- Concrete SDK execution, streaming policy, or cancellation ownership.
- Transcript mutation policy or session restore policy.

## AiChat public boundary

- Public surface stays reusable and feature-owned.
- `Ui/` emits view actions only.
- `Reducer/` owns request IDs, `CancelID`, and lifecycle routing.
- `Api/` owns external execution / persistence clients.
- `Model/` owns feature state and action taxonomy.

## FileManager host-only contract

- FileManager may adapt context and mount AiChat.
- FileManager must not own chat semantics, transcript policy, session policy, or model lifecycle.
- FileManager is limited to host wiring and pure context translation.

## Reducer-level AC before Wave 4

- `request_context_locked` is proven in reducer tests before integration.
- `next-request-only` model changes are proven in reducer tests before integration.
- `final transcript exactly-once` is proven in reducer tests before integration.
- Late / cancelled / superseded events do not mutate UI, transcript, or session state.
- Session restore and `new_session fallback` are reducer-tested before Wave 4.

## Spec tension note

`rebind_required` may appear in contract docs, but the MVP restore flow says restore failure or context mismatch should fall back to `new_session`. This plan uses the internal / ephemeral `rebind_required` interpretation only as a transient reducer fact, then applies the MVP `new_session fallback` unless direct source facts force a plan update.

## Verification commands executed

- `python3 - <<'PY' ...` — checked that the file contains `VOY-237`, `VOY-238`, `VOY-219`, `VOY-222`, `request_context_locked`, `next-request-only`, `final transcript exactly-once`, and `new_session fallback`.

## Verification results

- `TERMS_OK: True`
- `MISSING: []`
- `VOY-237: YES`
- `VOY-238: YES`
- `VOY-219: YES`
- `VOY-222: YES`
- `request_context_locked: YES`
- `next-request-only: YES`
- `final transcript exactly-once: YES`
- `new_session fallback: YES`
