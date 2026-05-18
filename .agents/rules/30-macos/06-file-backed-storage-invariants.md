---
alwaysApply: true
description: "Invariants for file-backed credential/auth storage in Voyager macOS."
---

# File-Backed Storage Invariants

## Applies when

- Writing or modifying file-backed credential, token, or auth storage under `apps/macos/**`.
- Any code that persists sensitive data to the local filesystem.

## Must

- Use `FileManager.replaceItemAt(_:withItemAt:)` for atomic writes. Not `moveItem` or direct writes.
- Acquire POSIX `flock` (via `open(O_CREAT | O_RDWR)`) before reading or writing storage files when concurrent access is possible.
- Set file permissions to `0600` (owner read/write only) after every write.
- When stored JSON is corrupt or unreadable, quarantine by renaming to a timestamped `.corrupted-*` backup and return empty/default state. Do not silently discard or overwrite.
- Use `@preconcurrency import Foundation` when Swift 6 actor isolation and `FileManager` calls require it.

## Must not

- Do not use `FileManager.moveItem` for atomic writes — use `replaceItemAt`.
- Do not leave storage files with default permissions after writes.
- Do not silently discard corrupt files — always quarantine first.
- Do not store secrets in plist, UserDefaults, or plain text files.

## Execution steps

1. Open the storage file with `O_CREAT | O_RDWR` and acquire `flock`.
2. Read and parse existing content; if corrupt, quarantine and return defaults.
3. Write updated content to a temporary file.
4. Atomically replace the original with `FileManager.replaceItemAt`.
5. Set permissions to `0600` on the new file.
6. Release `flock` and close file descriptor.

## Verification

- `grep -r 'replaceItemAt' apps/macos/Packages/**/Sources/` confirms atomic write usage.
- `grep -r '0600\|S_IRUSR' apps/macos/Packages/**/Sources/` confirms permission setting.
- `grep -r '\.corrupted' apps/macos/Packages/**/Sources/` confirms quarantine pattern.
- No `moveItem` usage in storage write paths.
