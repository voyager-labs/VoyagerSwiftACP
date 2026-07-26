# File Manager Illustration Design System

## 1. Atmosphere & Identity

The illustration mirrors Voyager's current macOS File Manager: a quiet native utility shell with translucent system materials, compact controls, and content-first density. Its signature is the sidebar extending beneath the transparent titlebar while the content and inspector share one inset, rounded main surface.

## 2. Color

All colors come from the `--macos-*` and `--fm-*` custom properties in `src/file-manager.css`. Sidebar, toolbar, content, inspector, selection, text, separator, focus, and status roles must use those tokens. No component-level raw colors are allowed.

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

Scroll ownership is explicit: sidebar tabs, entry content, AI messages, and inspector chat own their independent vertical scrolling. Window chrome, location shortcuts, toolbar, and breadcrumb/status remain fixed.

## 5. Components

### Native Window Shell

- **Structure:** full-height sidebar, accessible separator, inset rounded main surface, content pane, optional inspector separator and inspector.
- **States:** sidebar open/closed; inspector open/closed; persisted pane widths.
- **Accessibility:** separators expose orientation, controlled pane, pixel value, min/max, pointer drag, arrows, Shift+arrows, Home, and End.

### Sidebar

- **Structure:** titlebar controls, fixed location grid, scrollable pinned/unpinned tabs, New Tab row.
- **States:** active, hover, focus, revealed row action, empty tab collection.

### Content Chrome

- **Structure:** navigation controls, active title/composer area, hover/focus view and sort controls, New Chat, optional Show Sidebar, scroll body, breadcrumb/status.
- **States:** Home, browser, primary AI Chat, grid/list, sidebar closed.

### Contextual Inspector

- **Structure:** 40px chat-only header and chat body.
- **States:** Chat History, conversation, closed.

## 6. Motion & Interaction

Use existing `--fm-motion-*` durations. Motion communicates hover, focus, selection, pane resizing, or pane visibility only. Animate transform and opacity for decorative transitions; split widths follow direct pointer input without ornamental animation. Respect `prefers-reduced-motion`.

## 7. Depth & Surface

Use mixed native materials: translucent sidebar and toolbar, one clipped content/inspector material surface, subtle separators, and the existing window shadow. Do not introduce independent card styling into the shell.

## 8. Accessibility Constraints & Accepted Debt

- Target WCAG 2.2 AA semantics, full keyboard reachability, visible focus, and meaningful landmarks.
- Icons are inline SVG with accessible labels on their owning buttons; visible emoji icons are not permitted.
- Accepted debt: post-change browser and screenshot verification is intentionally omitted by explicit user request. Static structure, type, build, and catalog verification are required instead.
