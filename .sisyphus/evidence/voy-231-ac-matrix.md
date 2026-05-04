# VOY-231 AC Matrix

## Verification commands

| Command                                                                                                                                                                                                                  | Result                                                           |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------- |
| `xcrun swift test --package-path apps/macos/Packages/05_Entities/Ai`                                                                                                                                                     | Passed. Build complete. 197 tests passed, 3 skipped, 0 failures. |
| `xcrun swift test --package-path apps/macos/Packages/04_Features/AiChat`                                                                                                                                                 | Passed. Build complete. 14 tests passed, 0 failures.             |
| `xcodebuild -project "apps/macos/Voyager/Voyager.xcodeproj" -scheme Voyager-Dev -configuration Debug -derivedDataPath "/tmp/voyager-task8-dd" test -only-testing:VoyagerTests/FileManagerContentAiChatPresentationTests` | `** TEST SUCCEEDED **`; 3 passed cases.                          |
| `xcodebuild -project "apps/macos/Voyager/Voyager.xcodeproj" -scheme Voyager-Dev -configuration Debug -derivedDataPath "/tmp/voyager-task8-build-dd" build`                                                               | `** BUILD SUCCEEDED **`.                                         |

## Issue coverage

| Issue   | Evidence                                                                                                                                                    | Coverage                                                                                                                                                                                                                                                                          |
| ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| VOY-237 | `.sisyphus/evidence/task-4-entry-tests.txt`, `.sisyphus/evidence/task-7-filemanager-host.txt`, `.sisyphus/evidence/task-8-boundary-audit.txt`               | `testSetupBuildsUnconnectedEntryStateWithContextSummary` proves the entry/basic screen starts with current-context summary; FileManager host test proves the surface mounts without owning chat semantics.                                                                        |
| VOY-238 | `.sisyphus/evidence/task-4-model-tests.txt`, `.sisyphus/evidence/task-7-filemanager-host.txt`                                                               | `testModelSelectionIsNextRequestOnlyAndSameModelIsNoOp`, `testSetupFallsBackToFirstCatalogRowWhenSelectedModelIsUnresolvable`, and `testSelectedModelChangedFallsBackToFirstCatalogRowWithoutMutatingLockedModel` prove active model display and next-request-only model changes. |
| VOY-219 | `.sisyphus/evidence/task-5-stream-finalization.txt`, `.sisyphus/evidence/task-5-cancel-late-events.txt`, `.sisyphus/evidence/task-6-session-continuity.txt` | `testSubmitStreamsDraftOnlyAndFinalizesExactlyOnce` proves stream/finalization; `testCancelRejectsLateStreamAndFinalEvents` proves late events are ignored; `testPersistenceFailureCreatesRecoveryState` and regenerate coverage keep failure/retry behavior on the reducer side. |
| VOY-222 | `.sisyphus/evidence/task-6-session-restore.txt`, `.sisyphus/evidence/task-6-session-continuity.txt`                                                         | `testRestoreContextMismatchFallsBackToNewSession`, `testRestoreMissingRecordFallsBackToNewSessionWithoutError`, and `testRestoreValidSessionRestoresTranscriptAndNormalizesLockedState` prove restore/rebind fallback and continuity.                                             |

## Final decision

- Package tests: green.
- Focused FileManager test: green.
- Smoke build: green.
- Matrix path: `.sisyphus/evidence/voy-231-ac-matrix.md`
