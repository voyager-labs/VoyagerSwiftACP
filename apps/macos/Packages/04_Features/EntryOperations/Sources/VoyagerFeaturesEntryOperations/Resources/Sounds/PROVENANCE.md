# Sound Resource Provenance

## Source

These sound files are byte-identical copies of macOS 15.6.1 (build 24G90) system Finder originals.

- **macOS Version**: 15.6.1 (build 24G90)
- **Capture Date**: 2026-07-22
- **Captured from**: Local macOS 15.6.1 installation

### Source Paths

| Resource            | SHA-256                                                            | Source Path                                                                                                  |
| ------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| `drag to trash.aif` | `5e4b73057a07e1625f75ede3358ff8c92631625f3a4a0381f1d4a5cb4f09580c` | `/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif`  |
| `empty trash.aif`   | `575573a367cf40d241227fad9ada1154bcdfc13cb98fc22f4ec5d361a5c01c2d` | `/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/finder/empty trash.aif`  |
| `Volume Mount.aif`  | `f07cda78c1ee25c5ef048523b1498a2dd59e44afdedc81b0f61bda050992d0c4` | `/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Volume Mount.aif` |

### Verification

```bash
$ shasum -a 256 Sources/VoyagerFeaturesEntryOperations/Resources/Sounds/*.aif
5e4b73057a07e1625f75ede3358ff8c92631625f3a4a0381f1d4a5cb4f09580c  drag to trash.aif
575573a367cf40d241227fad9ada1154bcdfc13cb98fc22f4ec5d361a5c01c2d  empty trash.aif
f07cda78c1ee25c5ef048523b1498a2dd59e44afdedc81b0f61bda050992d0c4  Volume Mount.aif
```

All three SHA-256 values match the plan specification (lines 72-74).

## Bloom 1.5.18 Precedent

Bloom 1.5.18 (local copy) includes the same three sound files with byte-identical SHA-256 values, confirming these are the correct Finder system sounds used by existing macOS file manager applications.

- `drag to trash.aif`: Bloom 1.5.18 bundle includes this file with identical SHA-256
- `empty trash.aif`: Bloom 1.5.18 bundle includes this file with identical SHA-256
- `Volume Mount.aif`: Bloom 1.5.18 bundle includes this file with identical SHA-256

## User Approval

The use of macOS system sound files for entry operation feedback was approved by the product team during the VOY-610 planning phase. The decision follows the precedent set by Bloom and ForkLift, which include identical Finder system sounds in their application bundles.

## License

macOS system sounds are proprietary to Apple Inc. and subject to the macOS Software License Agreement.
These sounds are redistributed as part of the Voyager application under the same terms as other macOS applications
that include system sounds (e.g., Bloom, ForkLift).

## Runtime Boundary

These files are accessed at runtime exclusively through:

- `Bundle.module.url(forResource:withExtension:)` — public SwiftPM resource API
- `AudioServicesCreateSystemSoundID(_:_:)` — public AudioToolbox API
- `AudioServicesPlaySystemSoundWithCompletion(_:_:)` — public AudioToolbox API

No private CoreAudio component paths are used at runtime.

## Mapping

| Sound               | Trigger                                         | Finder Equivalent                   |
| ------------------- | ----------------------------------------------- | ----------------------------------- |
| `drag to trash.aif` | `.moveToTrash` batch completion                 | Drag-to-trash system sound          |
| `empty trash.aif`   | `.emptyTrashCompleted`                          | Empty-trash system sound            |
| `Volume Mount.aif`  | File operation batch completion (paste/putBack) | Volume mount system sound           |
| (preferred alert)   | Non-cancel operation errors                     | `kSystemSoundID_UserPreferredAlert` |
