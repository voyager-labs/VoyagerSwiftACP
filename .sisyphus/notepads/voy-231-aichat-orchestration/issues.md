- SourceKit `lsp_diagnostics` on isolated Voyager feature packages can report false macro/module errors (`ComposableArchitecture` / `ObservableState`) even when `xcrun swift test` passes. For scaffold tasks, treat SwiftPM build/test output as the actual compile gate and use diagnostics as a best-effort signal only.

- `AiModelCatalogRow` initializers place `subtitle` before `sortOrder`; tests need to spell `subtitle: nil` explicitly when they want to pass `sortOrder` by name without the compiler treating it as the subtitle argument.

- `uuid` dependency overrides in AiChat tests need a `UUIDGenerator` (`.incrementing` worked reliably); a plain closure returning `UUID` does not match the dependency type.

- F2 rejected FileManager `presentAiChat` because it only flipped `isAiChatPresented` and seeded context; the fix is to send `AiChatAction.setup` with a deterministic session id plus a minimal non-empty model catalog so `AiChatFeature` owns selection/session normalization.
