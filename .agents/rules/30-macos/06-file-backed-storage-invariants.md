---
description: "Invariants for file-backed credential/auth storage in Voyager macOS."
globs: "apps/macos/**/*.swift"
schemaVersion: 2
---

# File-Backed Storage Invariants

## Outcome

- This is the canonical owner for file-backed storage: concurrent mutation is locked, writes are atomic, files are `0600`, corrupt JSON is quarantined, and secrets never enter ordinary file storage.

## Default Actions

1. Open with `O_CREAT | O_RDWR` and acquire POSIX `flock` before concurrent read/write access.
2. Parse existing content; quarantine unreadable or corrupt JSON to a timestamped `.corrupted-*` backup and return empty/default state.
3. Write updated content to a temporary file, atomically replace with `FileManager.replaceItemAt(_:withItemAt:)`, set `0600`, then release the lock and close the descriptor.
4. Use `@preconcurrency import Foundation` where Swift 6 isolation requires it for `FileManager` calls.

## Decision Rules

- Apply this rule to credential, OAuth, provider snapshot, settings, and other file-backed storage changes.
- Acquire the lock whenever concurrent access is possible; do not weaken corruption recovery because a caller can recreate defaults.

## Stop Conditions

- Do not directly overwrite or use `FileManager.moveItem` as an atomic-write substitute.
- Do not leave default permissions, silently discard corrupt data, or store secrets in plist, `UserDefaults`, or plain-text files.

## Verification

- Confirm storage writes use `replaceItemAt`, locking where concurrent access is possible, `0600` permissions, and `.corrupted-*` quarantine.
- Confirm no `moveItem` is used in the touched storage write path and test corrupt-content recovery where that path changes.
