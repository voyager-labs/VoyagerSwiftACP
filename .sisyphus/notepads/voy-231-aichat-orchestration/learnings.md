- Wave 0 should freeze the contract before implementation: `request_context_locked`, `next-request-only`, `final transcript exactly-once`, and `new_session fallback` are the reducer proof points that prevent later integration churn.

- Wave 1 contract work fit cleanly into small `Model/` DTO files and `Api/` client protocols; keeping the request context snapshot frozen around existing `AiProvider`/`ProviderAuthMethod` values makes later AiChat wiring source-compatible without touching provider/auth APIs.

- The reusable chat boundary needs both a neutral current-context DTO (`references`/`items`/`attachments`) and persisted `transcriptHistory` in session snapshots; keeping those in `Model/` lets later AiChat own restore and replay policy without depending on FileManager or Pages.

- For isolated feature packages, SourceKit diagnostics can lag behind SwiftPM and misreport macro/plugin errors; a macro-free scaffold with plain `Reducer`/`Equatable` types keeps the package indexable while still following the same Model/Reducer/Ui split.

- For AiChat entry/model selection, storing `selectedModelHandle` and `lockedModelHandle` separately keeps the next-request-only rule obvious: `setup`/`onAppear` can normalize the selected handle to the first catalog row, while locked processing state remains untouched until an explicit cancel or later execution flow.

- Wave 2c proved the request-lock pattern: capture a request/run/context snapshot once on submit/regenerate, gate every stream/final/failure/persistence event by that immutable lock, and treat `lockedModelHandle` as the visible processing latch.

- In this TCA version, `TestStore.receive` exact-action assertions are easiest when `Action` conforms to `Equatable`; making `AiChatAction` equatable kept the lifecycle tests readable without relying on key-path-only receives.

- `uuid` dependency overrides in tests want a `UUIDGenerator`; `.incrementing` is the stable override when the test can assert against the emitted request context instead of hard-coding UUID values.

- Task 6 evidence is easier to keep honest when the restore filter commands are recorded with the exact observed test names, because `Restore` overlaps both fallback and continuity coverage in the same suite.

- Task 8 boundary auditing showed that `FileManager.default` references inside `Entities/Ai` are acceptable infrastructure usage, but the real boundary signal is whether imports or reducer/view ownership cross upward into Pages/App features.

- The focused `FileManagerContentAiChatPresentationTests` suite is the best host-only proof: it confirms the toolbar mount path stays presentational while chat semantics remain owned by `AiChat`.

- Final Verification Wave passed after rerunning F2: F1/F3/F4 approved initially, F2 approved once FileManager began sending `.aiChat(.setup(...))` with session/context/catalog/selected model; focused FileManager AiChat tests remained green.
