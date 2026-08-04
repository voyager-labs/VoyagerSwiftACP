# SF Symbol Rendering Contract

Read this reference for every File Manager control icon, navigation glyph, or system-symbol change.

## Canonical renderer

Use `apps/storybook/packages/file-manager-illustration/src/Foundations/SFSymbol.tsx` for every system icon. It renders the installed `symbolist` name-to-glyph mapping through the shared SF Symbols font stack.

Do not create, restore, or use custom SVG paths, an icon registry, or substitute artwork for a system control symbol.

## Source-first mapping

1. Read the owning native SwiftUI/AppKit control before selecting a symbol.
2. Copy the native `Image(systemName:)` name exactly into `SFSymbol`.
3. Preserve the native control's intended icon size and accessibility label at the calling component.
4. If the native source does not identify a symbol, inspect the control's implementation before choosing one. Do not infer it from a screenshot or generic convention.

For File Manager toolbar controls, the native sources are:

- `apps/macos/Packages/02_Pages/FileManager/Sources/VoyagerPagesFileManager/Content/Ui/ToolbarNavigationButtons.swift`
- `apps/macos/Packages/02_Pages/FileManager/Sources/VoyagerPagesFileManager/Content/Ui/ViewToggleButton.swift`
- `apps/macos/Packages/02_Pages/FileManager/Sources/VoyagerPagesFileManager/Content/Ui/SortGroupButton.swift`
- `apps/macos/Packages/02_Pages/FileManager/Sources/VoyagerPagesFileManager/Content/Ui/ToolbarView.swift`

## Mapping validity

`SFSymbol` intentionally renders nothing for an unknown `symbolist` name. Before shipping a new name, confirm the Storybook surface renders the control with a visible glyph.

This contract does not cover file thumbnails, previews, product marks, or other non-symbol visual content.

## Required verification

1. Run the affected package typecheck.
2. Open the affected Storybook state with `agent-browser`.
3. Confirm the labeled control is present and the symbol glyph is visible.
4. Confirm no custom SVG renderer or stale icon-registry import remains for the migrated system controls.
