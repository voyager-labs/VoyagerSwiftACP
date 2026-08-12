# File Manager Illustration Design System

## 1. Atmosphere & Identity

The illustration mirrors Voyager's current macOS File Manager: a quiet native utility shell with translucent system materials, compact controls, and content-first density. Its signature is the sidebar extending beneath the transparent titlebar while the content and inspector share one inset, rounded main surface.

## 2. Color

All macOS semantic colors come from `--macos-*` custom properties in `src/styles/macos-tokens.css`. File Manager aliases and shared/content styles remain in `src/styles/file-manager.css`. Reusable functional classes (flex, grid, inset, truncate, pointer) are defined in `src/styles/atoms.css`. Window shell, Sidebar, and Inspector styles are owned by `src/styles/window-shell.css`, `src/styles/sidebar.css`, and `src/styles/inspector.css`. Sidebar, toolbar, content, inspector, selection, text, separator, focus, and status roles must use those tokens. No component-level raw colors are allowed.

## 3. Typography

- Primary: SF Pro Text through `--fm-font-ui`.
- Display: SF Pro Display through the existing font-face declarations.
- Body, title, caption, and caption-2 sizes use the existing `--fm-font-size-*` scale.
- Control labels must remain legible at the native compact density and truncate rather than resize.

## 4. Spacing & Layout

- Base spacing unit: 4px, represented by the existing `--fm-space-*` scale.
- Default window: 960×510px; absolute minimum: 600×350px.
- Sidebar: 220px default, 150–280px resizable.
- Content: 400px minimum.
- Inspector: 300px default, 230px minimum.
- Main surface inset: 4px top, bottom, and right; also left when the sidebar is closed.
- Sidebar titlebar reserve: 50px.
- Content toolbar: 40px plus a 1px separator.
- Breadcrumb/status bar: 24px.
- Location grid: 42px cells, 12px horizontal padding, 8px gap.

Scroll ownership is explicit: sidebar tabs, entry content, and inspector chat own their independent vertical scrolling. Window chrome, location shortcuts, toolbar, and breadcrumb/status remain fixed.

## 5. Components

### Entry Thumbnail Visual Contract

Entry thumbnail SVGs are reference-image observations of macOS Finder thumbnails, not native-runtime proofs. All tokens are consumed through `--fm-entry-*` CSS custom properties; no raw component colors are allowed. SVG gradient IDs use distinct prefixes (`folder-*`, `doc-*`) to avoid collisions.

#### FolderIcon (Folder)

- **ViewBox:** `0 0 140 140`.
- **Silhouette:** broad, low folder occupying x=4..138.5, y=18..126. Rear body covers roughly 77% of canvas height.
- **Tab:** raised left tab with rounded top-left around x≈16,y=18, flat top to x≈47, then a smooth shoulder via x≈59,y≈26 into the body at x≈66,y≈34. No vertical step tab geometry.
- **Rear silhouette:** full folder back. Fill derived from `--fm-entry-folder-front` mixed with `--fm-entry-paper` (34% front + paper) to stay bright in both light and dark schemes. Stroke: `--fm-entry-accent-folder` at 30% transparency.
- **Pale rear insert:** inner pocket layer visible as a band from y≈28 to y=44 across most of the width. Fill: 18% `--fm-entry-folder-front` + paper. Stroke: accent at 20% transparency.
- **Front panel:** broad cyan body spanning x=6..138.5, beginning at y≈34..42, ending at y=126. Top-to-bottom `linearGradient` (78% front + paper at top, pure `--fm-entry-folder-front` at bottom) for clearly visible vertical depth. Stroke: `--fm-entry-accent-folder` at 42% transparency — a subtle blue edge, not a dark outline.
- **Top rim:** bright horizontal line (`--fm-entry-folder-highlight`) from x=8 to x=136 at y=36, stroke width 2.5.
- **Corners:** front panel has clearly rounded lower corners (radius ~8 viewBox units); top corners are slightly rounded.

#### FileIcon (Generic Document — `kind === "doc"`)

- **ViewBox:** `0 0 140 180` (tall portrait, scales inside the square wrapper).
- **Silhouette:** tall, narrow portrait page staying within x=2..136, y=3..176.
- **Page body:** top edge from left to x=89 at y=3, then diagonal cut to right edge at x=136, y=50. Right edge descends to y=168. Bottom-left and bottom-right corners are rounded (radius ~8 viewBox units). Left edge ascends to y=11 with a slight top-left corner rounding.
- **Fold flap:** begins at (89, 3), descends vertically to (89, 39), curves down/right via quadratic bezier (`Q 97 47`) to (105, 55), then meets the diagonal at (136, 50). This creates a large smooth folded-over corner, not a simple triangular cap.
- **Fold gradient:** diagonal `linearGradient` from `--fm-entry-edge` 18% mix (top-left) to `--fm-entry-fold` (bottom-right), applied to the fold flap path.
- **Paper gradient:** top-to-bottom `linearGradient` from pure `--fm-entry-paper` (near-white) at top to a 30% mix of `--fm-entry-edge` at bottom for clearly visible dimensional depth.
- **Exterior depth:** page-shaped path offset +4 viewBox units down/right, staying within x=6..140, y=7..180. Filled with `color-mix(in srgb, var(--fm-entry-graphite) 20%, transparent)`.
- **Corners:** rounded bottom corners (radius ~8 viewBox units); straight top corners except the folded corner.
- **Content:** fully blank — no label box, label text, or rule lines. This is the generic document state.

#### FileIcon (PDF — `kind === "pdf"`)

- Preserves the existing labelled-page rendering (viewBox `0 0 64 64`): label box with accent tint, "PDF" label text, and rule lines. Page shape and fold remain the same as before.

#### Scaling

- **Regular (64×64):** CSS `.entry-svg-icon` applies 64×64px sizing with `filter: var(--fm-entry-shadow-regular)`. All viewBoxes are scaled to this pixel size; the browser preserves aspect ratio.
- **Small (24×24 wrapper / 28×28 SVG):** CSS `.thumb-small` sets the wrapper to 24×24 and the `.entry-svg-icon` to 28×28 with `filter: var(--fm-entry-shadow-small)`. The SVG viewBox is unchanged; the browser scales the vector.
- **QuickLook:** parent wrapper scales the SVG 1.55× via CSS `transform: scale(1.55)`.
- **Constraint:** all three scaling tiers must preserve the silhouette — no element is hidden or added at different sizes.

### Native Window Shell

- **Structure:** full-height sidebar, accessible separator, inset rounded main surface, content pane, optional inspector separator and inspector.
- **States:** sidebar open/closed; inspector open/closed; persisted pane widths.
- **Accessibility:** separators expose orientation, controlled pane, pixel value, min/max, pointer drag, arrows, Shift+arrows, Home, and End.

### Sidebar

- **Structure:** titlebar controls, fixed location grid, scrollable pinned/unpinned tabs, New Tab row.
- **States:** active, hover, focus, revealed row action, empty tab collection.

### Content Chrome

- **Structure:** navigation controls, active title area, hover/focus view and sort controls, New Chat, optional Show Sidebar, scroll body, breadcrumb/status.
- **States:** Home, browser, grid/list, sidebar closed.

### Contextual Inspector

- **Structure:** 40px chat-only header and chat body.
- **States:** Chat History, conversation, closed.

### AI Chat Input Bar

- **Authority:** `VoyagerFeaturesAiChat/Ui/AiChatInputBar.swift`, its `AiChatInputDisplayModel`, and `AiChatView` placement rules.
- **Design Version axis:** `current` is the adopted native translation. `candidate-material-controls` is an unadopted Storybook proposal selected independently from appearance, macOS baseline, UI state, and geometry.
- **Current structure:** optional request-context sections, dynamically sized message field, plain text `+` attachment button, borderless native-menu model and thinking selectors, and one plain submit-or-stop button with the native SF Symbol glyph container.
- **Comparison structure:** preserves the same presentation and action contracts while using `IconButton` and `PopUpButton` in the footer and the AppKit `contentBackground` role on the chat input surface.
- **Geometry:** 8px internal padding and spacing, 46–160px message field height, 24×24px action control, 8px action radius, and a 16px Tahoe / 10px Sequoia composer radius.
- **Placement:** conversation uses 10px horizontal, 8px top, and 10px bottom outer padding; centered-empty uses the input bar without that outer inset.
- **States:** empty submit-disabled, draft submit-enabled, pending-resolution editing-disabled with stop, processing next-turn editing with stop, stop-disabled, unavailable model, populated request context, multiline maximum height, and 230px minimum inspector width.
- **Tokens:** `current` preserves the native solid chat input background through `--macos-chat-input-background-color` → `--fm-chat-composer-bg`. The comparison version maps the chat input surface through `--macos-material-content-background` → `--fm-chat-candidate-input-background`; footer controls continue to use the shared `--fm-control` roles.

### AI Chat Conversation

- **Authority:** `VoyagerFeaturesAiChat/Ui/AiChatConversationSurface.swift`, `AiChatAssistantMarkdownText.swift`, and `VoyagerDS` typography/surface roles.
- **User message:** right-aligned intrinsic bubble with a 16px minimum leading gutter, 14px horizontal and 10px vertical padding, 20px continuous radius, body typography, and `inputBackground` surface role.
- **Assistant message:** transparent full-width response with 12px internal block spacing and 4px vertical padding. Historical responses hide the visual Assistant header; waiting responses show the full title/status header.
- **Rich content:** assistant headings, paragraphs, bullets, numbered rows, blockquotes, tables, and fenced code follow native block ordering. Inline emphasis, strong text, links, and inline code preserve the native attributed-text intents. Body uses 13px typography with the native 16px AppKit line height and 8px block spacing; heading levels use 17/15/14px type with 20/18/17px line heights. Blockquotes use a 2px separator rail and 8px content gap. Tables own horizontal overflow, use 8px horizontal and 6px vertical cell padding, and tint the header with the control-background role. Code owns horizontal overflow, exposes its source-language header, and uses 12px monospaced typography with a 15px line height, an input-border stroke, 8px content padding, and an 8px radius.
- **Failure:** partial content remains visible before the 8px-spaced red failure row; contentless failure shows neither the header nor waiting indicator.
- **Affordances:** user and assistant output text remains browser-selectable as the Storybook translation of native AppKit selection. Deterministic copied/failed specimens use the native top-trailing capsule with the control-background role; they demonstrate presentation only, not pasteboard behavior or the native two-second lifecycle. Only the latest historical assistant response may expose the 28×28 regenerate action. Its hover label uses the native popover background and separator roles. Timestamp affordances occupy the user leading gutter or assistant top-trailing gutter without changing normal row flow.
- **Surface boundary:** assistant responses do not introduce an independent card background, border, radius, or fixed max-width.
- **Story harness:** isolated message stories render inside the 300px default inspector width. The user specimen retains the message-row alignment wrapper so its intrinsic bubble width and 16px minimum leading gutter remain observable. Integrated File Manager stories follow the window contract and may resize the inspector between its 230px minimum and 300px default when the viewport cannot fit the default 960px window plus stage insets.

## 6. Motion & Interaction

Use existing `--fm-motion-*` durations. Motion communicates hover, focus, selection, pane resizing, or pane visibility only. Animate transform and opacity for decorative transitions; split widths follow direct pointer input without ornamental animation. Respect `prefers-reduced-motion`.

## 7. Depth & Surface

Use mixed native materials: translucent sidebar and toolbar, one clipped content/inspector material surface, subtle separators, and the existing window shadow. Do not introduce independent card styling into the shell.

## 8. Accessibility Constraints & Accepted Debt

- Target WCAG 2.2 AA semantics, full keyboard reachability, visible focus, and meaningful landmarks.
- Icons are inline SVG with accessible labels on their owning buttons; visible emoji icons are not permitted.
- Browser verification: after every visual change, the agent must drive a real browser (agent-browser) to capture and inspect the affected states. Screenshot evidence is required before declaring a visual task complete.

## 9. Entry Thumbnail Static Fixtures

Entry thumbnail fixtures are **pre-generated macOS QuickLook thumbnails** stored as static PNG assets under `src/assets/entry-thumbnails/`. These are visual/reference completeness assets — not native-parity proofs.

### Provenance

Eight fixtures are generated by `scripts/generate-entry-thumbnail-fixtures.mjs` using macOS `qlmanage` (Quick Look generator) against a deterministic corpus under `fixtures/fixtures/`. Each generation records:

- Generator identity (script filename), macOS product/build version
- Source fixture key, relative path, and mode (`icon`, `content`, or `text-pdf-content`)
- `sourceSha256` and `outputSha256` for integrity verification

The `text` fixture has a two-step pipeline: `cupsfilter -m application/pdf` converts the TXT source to PDF, then `qlmanage` generates a content thumbnail from the PDF. This produces a readable white page with visible text texture instead of the dark/blank result qlmanage returns for raw `.txt` files. The mode is recorded as `text-pdf-content` to distinguish this preprocessing from direct `content` generation.

The provenance snapshot lives in `src/assets/entry-thumbnails/provenance.json`. The `verify-contract.mjs` script validates output existence, SHA-256 match, mode expectations, and exactly 8 entries.

### Fixture catalog

| Key        | Source                               | Mode             | Output              |
| ---------- | ------------------------------------ | ---------------- | ------------------- |
| `text`     | `documents/word/SampleDoc.txt`       | text-pdf-content | `text-sample.png`   |
| `pdf`      | `documents/pdf/sample-local-pdf.pdf` | icon             | `pdf-sample.png`    |
| `gif`      | `images/gif/hopper.gif`              | icon             | `gif-hopper.png`    |
| `word`     | `documents/word/checkboxes.docx`     | icon             | `office-word.png`   |
| `workbook` | `spreadsheets/excel/Booleans.xlsx`   | icon             | `office-excel.png`  |
| `pages`    | `documents/pages/일반 리포트.pages`  | icon             | `iwork-pages.png`   |
| `image`    | `images/png/hopper.png`              | content          | `image-hopper.png`  |
| `video`    | `media/video/test-1s.mp4`            | content          | `video-test-1s.png` |

### Renderer precedence

The `EntryThumbnail` component (`src/Entries/EntryThumbnail.tsx`) evaluates in this order:

1. **`thumbnailSrc` present** — renders an `<img>` with the provided URL/import path, including folder fixtures.
2. **No thumbnailSrc** — falls back to the kind-specific SVG icon (`FolderIcon`, `PdfIcon`, `ImageIcon`, `SheetIcon`, `VideoIcon`, `ArchiveIcon`, or generic `FileIcon`).

### Shared size scaling

All three scaling tiers apply identically to both generated thumbnails and SVG fallbacks:

- **Regular (64×64):** `.entry-thumbnail-image` renders at 64×64px with `filter: var(--fm-entry-shadow-regular)`.
- **Small (24×24 wrapper / 28×28 SVG):** CSS `.thumb-small` sets the wrapper to 24×24, image to 28×28 with `filter: var(--fm-entry-shadow-small)`.
- **QuickLook:** Parent wrapper scales the thumbnail 1.55× via CSS `transform: scale(1.55)`.

### Fallback behavior

- **Archive** has no generated thumbnail (Quick Look cannot generate previews for `.7z`); uses `ArchiveIcon` SVG.
- **Folder** without `thumbnailSrc` uses `FolderIcon` SVG; a folder fixture with `thumbnailSrc` renders its image preview.
- At least one no-thumbnail fallback entry is preserved per kind (`doc`, `pdf`, `image`, `sheet`, `video`, `archive`) in the root `files` data and the `entryKindEntries` array.

### Storybook wiring

Fixtures are imported into `mock-data.ts` via `entryThumbnailFixtures` from `src/data/entry-thumbnail-fixtures.ts`. Story data is centralized in `mock-data.ts`; individual story files import from there rather than maintaining local arrays. The `AllKindsAndSizes` comparison in `EntryThumbnailComparison` labels each entry as `{kind} preview` (has `thumbnailSrc`) or `{kind} fallback` (no `thumbnailSrc`) using the existing `thumbnailSrc` property — no new public props added.

### Not in scope

This is not a native-parity architecture. The fixtures are static reference images, not runtime-generated Quick Look previews. No AppKit bridge, no runtime filesystem access, and no CI-side generation is included.
